# Port of gradle-tools/SpecialTocTreeprocessor.groovy. Builds the "Learning Goals
# Overview" xref list and tags the first chapter "arabic-start" — robust-page-numbering.rb
# reads that role, so the two extensions MUST stay in sync.
require 'asciidoctor'
require 'asciidoctor/extensions'

module ISAQB
  class LearningGoalsOverview < Asciidoctor::Extensions::Treeprocessor
    def process document
      language = document.attr 'language'
      section_title = language == 'DE' ? 'Lernziele im Überblick' : 'Learning Goals Overview'

      learning_goals = document.blocks.flat_map { |block| find_learning_goals block }
      return document if learning_goals.empty?

      learning_goals.sort_by!(&:id)

      overview = create_section document, section_title, {}, level: 1
      # Treeprocessor-created sections skip auto id generation; set one so xrefs resolve.
      overview.id = 'learning-goals-overview'
      overview.numbered = false

      list = create_list overview, :ulist
      overview.blocks << list

      top_sections = document.blocks.select { |b| b.context == :section }
      copyright_section = top_sections.find { |b| b.id == 'copyright' } || top_sections.first

      first_chapter = top_sections.find { |b| b != copyright_section }
      first_chapter&.add_role 'arabic-start'

      # Order: copyright, TOC, overview, chapters.
      if copyright_section
        document.blocks.insert document.blocks.index(copyright_section) + 1, overview
      else
        idx = first_chapter ? document.blocks.index(first_chapter) : 0
        document.blocks.insert idx, overview
      end

      learning_goals.each do |section|
        clean_title = clean_title_for_xref section.title
        list.blocks << (create_list_item list, "xref:#{section.id}[#{clean_title}]")
      end

      document
    end

    private

    # Turn the converted title's HTML sup/sub + entities back into AsciiDoc inline markup.
    def clean_title_for_xref title
      title = title.gsub(%r{<sup>(.*?)</sup>}, '^\1^')
      title = title.gsub(%r{<sub>(.*?)</sub>}, '~\1~')
      title = unescape_html_entities title
      escape_for_xref title
    end

    def unescape_html_entities input
      input.gsub('&amp;', '&')
           .gsub('&lt;', '<')
           .gsub('&gt;', '>')
           .gsub('&quot;', '"')
           .gsub('&#39;', "'")
    end

    def escape_for_xref input
      input.gsub('[', '&#91;').gsub(']', '&#93;')
    end

    # Learning goals are sections; sections only ever nest inside sections, never inside
    # dlists/lists/tables (whose #blocks yield Arrays, not Blocks). Recurse sections only.
    def find_learning_goals block
      return [] unless block.respond_to?(:context) && block.context == :section

      result = []
      id = block.id
      result << block if id && (id.start_with?('LG') || id.start_with?('LZ'))
      block.blocks.each { |child| result.concat find_learning_goals child }
      result
    end
  end
end

Asciidoctor::Extensions.register do
  treeprocessor ISAQB::LearningGoalsOverview
end
