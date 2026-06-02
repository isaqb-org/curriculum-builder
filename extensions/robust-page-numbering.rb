require 'asciidoctor/pdf'

# Roman front matter up to the first chapter, arabic from it. The treeprocessor tags that
# chapter "arabic-start"; here we read its physical page and use (page - 1) as the
# front-matter page count, so the boundary is robust regardless of front-matter length.
module ISAQB
  module RomanFrontMatter
    def convert_section sect, opts = {}
      result = super
      if @isaqb_front_matter_pages.nil? && (sect.role? 'arabic-start')
        @isaqb_front_matter_pages = (sect.attr 'pdf-page-start').to_i - 1
      end
      result
    end

    def isaqb_front_matter_pages(fallback)
      @isaqb_front_matter_pages || fallback
    end

    def ink_running_content(periphery, doc, skip = [1, 1], body_start_page_number = 1)
      skip = [skip[0], isaqb_front_matter_pages(skip[1])]
      super periphery, doc, skip, body_start_page_number
    end

    def ink_toc(doc, num_levels, toc_page_number, start_cursor, num_front_matter_pages = 0)
      num_front_matter_pages = isaqb_front_matter_pages(num_front_matter_pages)
      super
    end

    def add_outline(doc, num_levels, toc_page_nums, num_front_matter_pages, has_front_cover)
      num_front_matter_pages = isaqb_front_matter_pages(num_front_matter_pages)
      super
    end
  end
end

Asciidoctor::PDF::Converter.prepend ISAQB::RomanFrontMatter
