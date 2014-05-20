require 'active_support/all'
require 'open-uri'
require 'nokogiri'

require_relative 'date_parser'
require_relative 'string'
mann_url = "https://www.mann-hummel.com/mf_prodkata_eur/index.html?ktlg_page=1&ktlg_lang=8"
manufacturers_doc = Nokogiri::HTML(open(mann_url, "User-Agent" => "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.2.1) Gecko/20100122 firefox/3.6.1")) do |config|
  config.strict.noblanks # avoids a lot of whitespaces
end
$outputfile=File.open("car_models.yml",'a')
manufacturers_doc.css('select[name="ktlg_01_mrksl"] option').each do |manufacturer|
  manufacturer_id = manufacturer['value'].to_i
  unless manufacturer_id.zero?
    manufacturer_title = manufacturer.content.strip.titleize
    puts "#{manufacturer_title}"
    $outputfile.write "#{manufacturer_title}\n"
    # Retrieving manufacturers
    models_url = "#{mann_url}&ktlg_01_fzart=1&ktlg_01_fzkat=0&ktlg_01_mrksl=#{manufacturer_id}"
    models_doc = Nokogiri::HTML(open(models_url)) do |config|
      config.strict.noent # avoids a lot of whitespaces
    end

    models_doc.css('select[name="ktlg_01_mdrsl"] option').each do |model|
      model_id = model['value'].to_i
      unless model_id.zero?
        model_data = model.inner_text.strip.split('|')
        model_title = model_data.first.delete_live_breakes.delete_nbsp.strip
        model_years = DateParser::normalize_range(model_data.last.strip.delete_live_breakes.delete_nbsp)
        puts "  #{model_title}|#{model_years}"
        $outputfile.write "  #{model_title}|#{model_years}\n"
        modifications_url = "#{mann_url}&ktlg_01_fzart=1&ktlg_01_fzkat=0&ktlg_01_mrksl=#{manufacturer_id}&ktlg_01_mdrsl=#{model_id}&ktlg_c001_flag=1"

        begin
          sleep 1
          modifications_doc = Nokogiri::HTML(open(modifications_url)) do |config|
            config.strict.noent # avoids a lot of whitespaces
          end
          modifications_doc.css('#rahmen tr').each do |modification|
            if modification.css('td nobr').count > 2 # Only real lines, without table headers
              cells = []
              info = {}
              modification.css('td').each do |cell|
                cells << cell.content.delete_live_breakes.delete_nbsp.strip
              end
              cells[9] = DateParser::normalize_range(cells[9]) if cells[9] # Parsing dates
              info[:modification], info[:engine], info[:watts], info[:horses], info[:production] = cells[1], cells[3], cells[5], cells[7], cells[9]
              puts "    #{info[:modification]}|#{info[:engine]}|#{info[:horses]}|#{info[:production]}"
              $outputfile.write "    #{info[:modification]}|#{info[:engine]}|#{info[:horses]}|#{info[:production]}\n"
            end
          end
        rescue
          puts "FAIL: #{modifications_url}"
          $outputfile.write "FAIL: #{modifications_url}\n"
          # retry
        end
      end
    end
    sleep 2
  end
end
$outputfile.close
