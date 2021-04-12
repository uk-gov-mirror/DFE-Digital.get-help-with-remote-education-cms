class GovspeakDecorator < DelegateClass(Govspeak::Document)
  Govspeak::Document.extension("YoutubeVideo", /\$YoutubeVideo(?:\[(.*?)\])?\((.*?)\)\$EndYoutubeVideo/m) do |title, youtube_link|
    youtube_id = youtube_link.scan(/^.*(youtu.be\/|v\/|u\/\w\/|embed\/|watch\?v=|&v=)([^#&?]*).*/)[0][1]
    embed_url = %(https://www.youtube.com/embed/#{youtube_id}?enablejsapi=1&amp;origin=https%3A%2F%2Fwww.help-for-early-years.education.gov.uk)
    optional_title = title ? %(title="#{title}") : ""
    %(<div class="govspeak-embed-container"><iframe class="govspeak-embed-video" src="#{embed_url}" #{optional_title} frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen=""></iframe></div>)
  end
  Govspeak::Document.extension("Accordion", /\$Accordion\s*$(.*?)\s*\$EndAccordion/m) do |body|
    index = 1
    accordion_index = 1
    # accordion_index = self.accordion_index
    # self.accordion_index += 1
    lines = []
    body.scan(/\$Heading\s*(.*?)\s*\$EndHeading\s*\$Summary\s*(.*?)\s*\$EndSummary\s*\$Content\s*(.*?)\s*\$EndContent/m) do |heading, summary, content|
      if summary.present?
        summary = %(<div>#{summary}</div>)
      end
      lines << %(<div class="govuk-accordion__section ">)
      lines << %(<div class="govuk-accordion__section-header">)
      lines << %(<h2 class="govuk-accordion__section-heading">)
      lines << %(<span class="govuk-accordion__section-button" id="accordion-#{accordion_index}-heading-#{index}">#{heading}</span>)
      lines << %(</h2>)
      lines << summary
      lines << %(</div>)
      lines << %(<div id="accordion-#{accordion_index}-content-#{index}" class="govuk-accordion__section-content" aria-labelledby="accordion-#{accordion_index}-heading-#{index}">)
      lines << %(<div class='govuk-body'>#{content}</div>)
      lines << %(</div>)
      lines << %(</div>)
      index = index + 1
    end
    %(<div class="govuk-accordion" data-module="govuk-accordion" id="accordion-#{accordion_index}">#{lines.join}</div>)
  end


  def to_html
    @to_html ||= begin
      html = if sanitize? # @options[:sanitize]
               raw_html = HtmlSanitizerDecorator.new(kramdown_doc.to_html)
               raw_html.sanitize(allowed_elements: allowed_elements)
             else
               kramdown_doc.to_html
             end
      Govspeak::PostProcessor.process(html, self)
    end
  end

  def sanitize?
    __getobj__.instance_variable_get(:@options)[:sanitize] == true
  end

  def kramdown_doc
    __getobj__.send("kramdown_doc")
  end

  def allowed_elements
    __getobj__.instance_variable_get(:@allowed_elements)
  end

  class HtmlSanitizerDecorator < Govspeak::HtmlSanitizer
    class YoutubeTransformer
      def call(sanitize_context)
        node      = sanitize_context[:node]
        node_name = sanitize_context[:node_name]

        # Don't continue if this node is already allowlisted or is not an element.
        return if sanitize_context[:is_allowlisted] || !node.element?

        # Don't continue unless the node is an iframe.
        return unless node_name == "iframe"

        # Verify that the video URL is actually a valid YouTube video URL.
        return unless node["src"] =~ %r{\A(?:https?:)?//(?:www\.)?((youtube)|(youtu\.be))(?:-nocookie)?\.com/}

        # We're now certain that this is a YouTube embed, but we still need to run
        # it through a special Sanitize step to ensure that no unwanted elements or
        # attributes that don't belong in a YouTube embed can sneak in.
        Sanitize.node!(node, {
          elements: %w[iframe],

          attributes: {
            "iframe" => %w[class allowfullscreen frameborder height src width title allow],
          },
        })

        # Now that we're sure that this is a valid YouTube embed and that there are
        # no unwanted elements or attributes hidden inside it, we can tell Sanitize
        # to allowlist the current node.
        { node_allowlist: [node] }
      end
    end

    def sanitize(allowed_elements: [])
      transformers = [TableCellTextAlignWhitelister.new, YoutubeTransformer.new]
      if @allowed_image_hosts && @allowed_image_hosts.any?
        transformers << ImageSourceWhitelister.new(@allowed_image_hosts)
      end

      Sanitize.clean(@dirty_html, Sanitize::Config.merge(
        Sanitize::Config::RELAXED,
        elements: allowed_elements,
        attributes: {
          "div" => [:data],
        },
        transformers: transformers
      ))
    end
  end
end
