module WPScan
  module Finders
    module MainTheme
      # From the css style
      class CssStyle < CMSScanner::Finders::Finder
        include Finders::WpItems::URLsInHomepage

        def create_theme(name, style_url, opts)
          WPScan::Theme.new(
            name,
            target,
            opts.merge(found_by: found_by, confidence: 70, style_url: style_url)
          )
        end

        def passive(opts = {})
          res = Browser.get(target.url)

          passive_from_css_href(res, opts) || passive_from_style_code(res, opts)
        end

        def passive_from_css_href(res, opts)
          target.in_scope_urls(res, '//style|//link') do |url|
            next unless Addressable::URI.parse(url).path =~ %r{/themes/([^\/]+)/style.css\z}i

            return create_theme(Regexp.last_match[1], url, opts)
          end
          nil
        end

        def passive_from_style_code(res, opts)
          res.html.css('style').each do |tag|
            code = tag.text.to_s
            next if code.empty?

            next unless code =~ %r{#{item_code_pattern('themes')}\\?/style\.css[^"'\( ]*}i

            return create_theme(Regexp.last_match[1], Regexp.last_match[0].strip, opts)
          end
          nil
        end
      end
    end
  end
end