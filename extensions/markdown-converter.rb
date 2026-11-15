# Asciidoctor converter that writes GitHub Flavored Markdown (backend "markdown", file suffix .md).
#
# Asciidoctor parses the document as usual (includes, language tags, conditionals, attributes,
# extensions such as learning-goals-overview.rb), so the Markdown contains exactly the content of
# the PDF/HTML output. This converter only decides how each node is written as Markdown.
#
# Usage: asciidoctor -r ./markdown-converter.rb -b markdown doc.adoc
#
# Design decisions:
# - No HTML in the output, so that it reads the same in every Markdown viewer and for AI agents.
# - Paragraphs and list items are written on a single line (AsciiDoc's one-sentence-per-line
#   source would otherwise need careful escaping of line starts). Hard line breaks become Markdown
#   line breaks (two trailing spaces).
# - Links to websites stay links. Cross references within the document become plain text (e.g.
#   "LG 01-02: ..." or "[Bass+2021]"); there are no anchors.
# - Superscript/subscript use Unicode characters where possible (x², CO₂), otherwise plain text (®).
# - GFM tables need a header row and cannot contain blocks: tables without a header get an empty
#   one, multi-line cell content is joined with "; ".
# - Admonitions become GitHub alerts (> [!NOTE]); sidebars and quotes become blockquotes.
require 'asciidoctor'

module ISAQB
  class MarkdownConverter < Asciidoctor::Converter::Base
    register_for 'markdown'

    ADMONITION_TYPES = %w[NOTE TIP IMPORTANT WARNING CAUTION].freeze

    # Asciidoctor applies its inline substitutions one after another to the already converted
    # text, so Markdown emitted for **strong** would be matched again by the *constrained* rule.
    # Inline markup is therefore written with placeholders (Unicode private use characters) and
    # replaced by the real Markdown characters once the whole document is converted.
    STAR = "\u{E000}"
    TICK = "\u{E001}"
    # Hard line break; becomes "  \n" (or a space where a line break is impossible).
    BREAK = "\u{E002}"

    SUPERSCRIPT = '0123456789+-=()ni'.chars.zip('⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ⁿⁱ'.chars).to_h.freeze
    SUBSCRIPT = '0123456789+-=()'.chars.zip('₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎'.chars).to_h.freeze

    def initialize backend, opts = {}
      super
      init_backend_traits basebackend: 'markdown', filetype: 'md', outfilesuffix: '.md', supports_templates: false
    end

    # ---------------------------------------------------------------- document structure

    def convert_document node
      parts = [front_matter(node)]
      if node.header? && !node.notitle && (title = node.doctitle)
        parts << "# #{heading_text title}"
      end
      parts << blocks(node)
      parts << footnotes(node)
      finish parts
    end

    def convert_embedded node
      finish [blocks(node), footnotes(node)]
    end

    def convert_section node
      title = node.title
      if node.caption
        title = "#{node.caption}#{title}"
      elsif node.numbered && node.level <= (node.document.attr 'sectnumlevels', 3).to_i
        title = "#{node.sectnum} #{title}"
      end
      [heading(node.level + 1, title), blocks(node)].reject(&:empty?).join "\n\n"
    end

    def convert_floating_title node
      heading node.level + 1, node.title
    end

    def convert_preamble node
      blocks node
    end

    def convert_open node
      with_title node, blocks(node)
    end

    def convert_example node
      with_title node, blocks(node)
    end

    def convert_toc _node
      ''
    end

    def convert_page_break _node
      ''
    end

    def convert_thematic_break _node
      '---'
    end

    # ---------------------------------------------------------------- text blocks

    def convert_paragraph node
      with_title node, one_line(prose(node.content))
    end

    def convert_admonition node
      type = node.attr('name').to_s.upcase
      type = 'NOTE' unless ADMONITION_TYPES.include? type
      body = node.content_model == :compound ? blocks(node) : one_line(prose(node.content))
      body = "**#{prose node.title}**\n\n#{body}" if node.title?
      quote "[!#{type}]\n#{body}"
    end

    def convert_sidebar node
      body = blocks node
      body = "**#{prose node.title}**\n\n#{body}" if node.title?
      quote body
    end

    def convert_quote node
      body = node.content_model == :compound ? blocks(node) : one_line(prose(node.content))
      attribution = [node.attr('attribution'), node.attr('citetitle')].compact.map { |a| prose a }
      body = "#{body}\n\n— #{attribution.join ', '}" unless attribution.empty?
      with_title node, quote(body)
    end

    def convert_verse node
      body = prose(node.content).split("\n").join "  \n"
      with_title node, quote(body)
    end

    def convert_listing node
      lang = node.attr 'language'
      with_title node, fenced(code(node.content), lang)
    end

    def convert_literal node
      with_title node, fenced(code(node.content))
    end

    def convert_stem node
      with_title node, "$$\n#{code node.content}\n$$"
    end

    def convert_pass node
      node.content
    end

    # ---------------------------------------------------------------- lists

    def convert_ulist node
      marker = node.option?('checklist') ? nil : '-'
      items = node.items.map do |item|
        prefix = marker || (item.attr?('checked') ? '- [x]' : '- [ ]')
        list_item prefix, item
      end
      with_title node, join_items(node, items)
    end

    def convert_olist node
      start = (node.attr 'start', 1).to_i
      items = node.items.each_with_index.map { |item, i| list_item "#{start + i}.", item }
      with_title node, join_items(node, items)
    end

    def convert_colist node
      convert_olist node
    end

    def convert_dlist node
      items = node.items.map do |terms, desc|
        term = terms.map { |t| prose t.text }.join ', '
        text = desc&.text? ? one_line(prose(desc.text)) : ''
        first = "- **#{term}**#{text.empty? ? '' : ": #{text}"}"
        nested = desc&.blocks? ? blocks(desc) : ''
        nested.empty? ? first : "#{first}\n\n#{indent nested, 2}"
      end
      with_title node, items.join("\n")
    end

    # ---------------------------------------------------------------- tables

    def convert_table node
      columns = node.columns
      head = node.rows.head
      body = node.rows.body + node.rows.foot

      header_cells = head.empty? ? Array.new(columns.size, '') : row_cells(head.first, columns.size)
      body = head.drop(1) + body
      alignments = columns.map do |col|
        case col.attr 'halign'
        when 'center' then ':---:'
        when 'right' then '---:'
        else '---'
        end
      end

      lines = [table_row(header_cells), table_row(alignments)]
      body.each { |row| lines << table_row(row_cells(row, columns.size)) }

      parts = []
      parts << "**#{prose node.captioned_title}**" if node.title?
      parts << lines.join("\n")
      parts.join "\n\n"
    end

    # ---------------------------------------------------------------- images and media

    def convert_image node
      target = node.attr 'target'
      alt = node.attr('alt').to_s
      image = "![#{escape_brackets alt}](#{node.image_uri target})"
      image = "[#{image}](#{node.attr 'link'})" if node.attr? 'link'
      parts = [image]
      parts << "*#{prose node.captioned_title}*" if node.title?
      parts.join "\n\n"
    end

    def convert_video node
      with_title node, "[Video](#{node.attr 'target'})"
    end

    def convert_audio node
      with_title node, "[Audio](#{node.media_uri(node.attr 'target')})"
    end

    # ---------------------------------------------------------------- inline nodes

    def convert_inline_quoted node
      text = node.text
      result =
        case node.type
        when :strong then "#{STAR * 2}#{text}#{STAR * 2}"
        when :emphasis then "#{STAR}#{text}#{STAR}"
        # Entities stay encoded here: later substitutions (e.g. unescaping \<<xref>>) still need them.
        # prose decodes code spans verbatim once the paragraph is complete.
        when :monospaced then "#{TICK}#{text}#{TICK}"
        when :superscript then script(text, SUPERSCRIPT)
        when :subscript then script(text, SUBSCRIPT)
        when :double then "“#{text}”"
        when :single then "‘#{text}’"
        when :asciimath, :latexmath then "$#{code text}$"
        else text
        end
      result
    end

    def convert_inline_anchor node
      case node.type
      when :link
        target = node.target
        text = node.text
        "[#{escape_brackets text}](#{target})"
      when :xref
        refid = node.attributes['refid'] || node.target.to_s.delete_prefix('#')
        text = node.text || xref_text(node, refid) || "[#{refid}]"
        # Reference to another document: keep the link. Within the document: plain text.
        (path = node.attributes['path']) ? "[#{escape_brackets text}](#{path})" : text
      when :ref
        ''
      when :bibref
        "[#{node.reftext || node.id}]"
      else
        node.text.to_s
      end
    end

    def convert_inline_break node
      "#{node.text}#{BREAK}"
    end

    def convert_inline_image node
      "![#{escape_brackets node.attr('alt').to_s}](#{node.image_uri node.target})"
    end

    def convert_inline_footnote node
      if (index = node.attr 'index')
        "[^#{index}]"
      else
        node.text.to_s
      end
    end

    def convert_inline_kbd node
      keys = node.attr 'keys'
      keys.join '+'
    end

    def convert_inline_button node
      "#{STAR * 2}[#{node.text}]#{STAR * 2}"
    end

    def convert_inline_menu node
      [node.attr('menu'), *node.attr('submenus'), node.attr('menuitem')].compact.join ' › '
    end

    def convert_inline_indexterm node
      node.type == :visible ? node.text : ''
    end

    def convert_inline_callout _node
      ''
    end

    def convert_inline_button_fallback node
      node.text.to_s
    end

    private

    # Converts all child blocks and separates them with a blank line.
    def blocks node
      node.blocks.map(&:convert).map(&:to_s).reject { |s| s.strip.empty? }.join "\n\n"
    end

    def finish parts
      text = parts.reject { |p| p.nil? || p.strip.empty? }.join("\n\n")
      text = text.gsub(/#{BREAK}[ \t]*\n?[ \t]*/o, "  \n").tr("#{STAR}#{TICK}", '*`')
      "#{text.gsub(/\n{3,}/, "\n\n").strip}\n"
    end

    # YAML front matter with metadata for tools and AI agents. Fields without a value are omitted.
    # md-pdf-file and md-valid-from are set by build.sh.
    def front_matter node
      german = node.attr('language').to_s.upcase == 'DE'
      copyright = node.catalog[:refs]['copyright']
      copyright_title = copyright.is_a?(Asciidoctor::Section) ? plain(heading_text(copyright.title)) : nil

      license =
        if copyright_title
          german ? "Die Nutzung unterliegt den Bedingungen im Abschnitt '#{copyright_title}'." : "Use is subject to the conditions in the section '#{copyright_title}'."
        end
      generated =
        if german
          'Aus den AsciiDoc-Quellen des Lehrplans generiert. Inhaltlich identisch mit der PDF- und HTML-Version.'
        else
          'Generated from the AsciiDoc sources of the curriculum. Same content as the PDF and HTML versions.'
        end

      fields = {
        'title' => (node.doctitle && plain(heading_text(node.doctitle))),
        'publisher' => 'iSAQB e. V.',
        'language' => node.attr('language')&.downcase,
        'version' => node.attr('release-version'),
        'date' => iso_date(node.attr('revdate')),
        'valid-from' => node.attr('md-valid-from'),
        'pdf' => node.attr('md-pdf-file'),
        'license' => license,
        'generated' => generated
      }.reject { |_, v| v.nil? || v.to_s.empty? }

      lines = fields.map { |k, v| %(#{k}: "#{v.to_s.gsub('\\', '\\\\\\\\').gsub('"', '\\"')}") }
      "---\n#{lines.join "\n"}\n---"
    end

    # 20261113 -> 2026-11-13; anything else unchanged
    def iso_date value
      value.to_s.sub(/\A(\d{4})(\d{2})(\d{2})\z/, '\1-\2-\3')
    end

    # Text without Markdown markup (for YAML values)
    def plain text
      text.delete("#{STAR}#{TICK}").gsub('\<', '<')
    end

    def footnotes node
      notes = node.footnotes
      return '' if notes.empty?

      notes.map { |fn| "[^#{fn.index}]: #{one_line prose(fn.text)}" }.join "\n"
    end

    def heading level, title
      text = heading_text title
      return "**#{text}**" if level > 6

      "#{'#' * level} #{text}"
    end

    # Headings must be a single line; line breaks (hard breaks, <br> passed through as title break)
    # become a space.
    def heading_text title
      one_line(prose(title).gsub(/(?:\s*(?:<br\s*\/?>|#{BREAK})\s*)+/o, ' ')).strip
    end

    def with_title node, body
      return body unless node.title?

      "**#{one_line prose(node.title)}**\n\n#{body}"
    end

    # x^2^ -> x², CO~2~ -> CO₂; text without Unicode equivalent (e.g. ®) stays plain.
    def script text, map
      text.chars.all? { |c| map.key? c } ? text.chars.map { |c| map[c] }.join : text
    end

    def list_item marker, item
      text = one_line prose(item.text)
      first = "#{marker} #{text}"
      return first unless item.blocks?

      "#{first}\n\n#{indent blocks(item), marker.length + 1}"
    end

    # Tight list unless an item contains nested blocks.
    def join_items node, items
      loose = node.items.any? { |item| item.respond_to?(:blocks?) && item.blocks? && item.blocks.any? { |b| b.context != :ulist && b.context != :olist } }
      items.join(loose ? "\n\n" : "\n")
    end

    def indent text, width
      pad = ' ' * width
      text.split("\n", -1).map { |l| l.empty? ? l : "#{pad}#{l}" }.join "\n"
    end

    def quote text
      text.split("\n", -1).map { |l| l.empty? ? '>' : "> #{l}" }.join "\n"
    end

    def fenced text, lang = nil
      fence = '```'
      fence += '`' while text.include? fence
      "#{fence}#{lang}\n#{text}\n#{fence}"
    end

    def row_cells row, size
      cells = []
      row.each do |cell|
        cells << cell_text(cell)
        ((cell.colspan || 1) - 1).times { cells << '' }
      end
      cells.fill '', cells.size...size
    end

    def cell_text cell
      text =
        case cell.style
        when :asciidoc then cell.content
        when :literal then code(cell.text)
        else Array(cell.content).map { |p| prose p }.join("\n\n")
        end
      # One line per cell: list markers are dropped, lines joined with "; ".
      lines = text.gsub(/#{BREAK}/o, "\n").split("\n").map(&:strip).reject(&:empty?)
      lines.map { |l| l.sub(/\A(?:[-*]|\d+\.)\s+/, '') }.join('; ').gsub('|', '\|')
    end

    def table_row cells
      "| #{cells.join ' | '} |"
    end

    def xref_text node, refid
      ref = node.document.catalog[:refs][refid]
      return nil unless ref.is_a? Asciidoctor::AbstractNode

      ref.xreftext node.attr('xrefstyle', nil, true)
    end

    def one_line text
      text.to_s.gsub(/\s*\n\s*/, ' ')
    end

    def escape_brackets text
      text.to_s.gsub('[', '\[').gsub(']', '\]')
    end

    # Text in prose: decode the entities Asciidoctor produced. A literal "<" is escaped so that it
    # is not taken for an HTML tag.
    # Code spans (between TICK placeholders) are decoded verbatim instead.
    def prose text
      text.to_s.split(/(#{TICK}[^#{TICK}]*#{TICK})/o).map do |part|
        part.start_with?(TICK) ? code(part) : prose_segment(part)
      end.join
    end

    def prose_segment text
      decode_numeric(text)
        .gsub('&lt;', '\<')
        .gsub('&gt;', '>')
        .gsub('&quot;', '"')
        .gsub('&apos;', "'")
        .gsub('&amp;', '&')
    end

    # Text in code (spans, blocks): fully decoded, Markdown shows it verbatim.
    def code text
      decode_numeric(text.to_s)
        .gsub('&lt;', '<')
        .gsub('&gt;', '>')
        .gsub('&quot;', '"')
        .gsub('&apos;', "'")
        .gsub('&amp;', '&')
    end

    def decode_numeric text
      text.gsub(/&#(\d+);/) { [Regexp.last_match(1).to_i].pack 'U' }
          .gsub(/&#x(\h+);/i) { [Regexp.last_match(1).hex].pack 'U' }
    end
  end
end
