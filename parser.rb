require 'active_support/all'
require 'open-uri'
require 'nokogiri'
require 'unicode'
require 'colorize'


require_relative 'date_parser'
require_relative 'string'

class NilClass
  def empty?
    true
  end
end

mann_url = "https://www.mann-hummel.com/mf_prodkata_eur/index.html?ktlg_page=1&ktlg_lang=1"
manufacturers_doc = Nokogiri::HTML(open(mann_url, "User-Agent" => "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.2.1) Gecko/20100122 firefox/3.6.1")) do |config|
  config.strict.noblanks # avoids a lot of whitespaces
end

already_parsed = {}
manufacturer_name = ""
car_series_name = ""
model_name = ""
outfile = "car_models.yml"

if File.exist?(outfile)
  File.open(outfile,'r').read.each_line do |line|
    if line[/^\S+/]
      manufacturer_name = line.strip
      already_parsed[manufacturer_name] = {}
    elsif line[/^\s\s\S+/]
      a_line = line.strip.split('|')
      car_series_name = a_line[0]
      already_parsed[manufacturer_name][car_series_name] = {serie: car_series_name, life_time: a_line[1].gsub(/[\]\[]/,''), models: []}
    elsif line[/^\s\s\s\s\S+/]
      model_params = line.strip.split('|')
      already_parsed[manufacturer_name][car_series_name][:models] << {
        model_name: model_params[0],
        engines: model_params[1],
        power_hp: model_params[2],
        life_time: model_params[3].gsub(/[\]\[]/,'')
      }
    end
  end
end

#puts already_parsed.to_json
#return

$outputfile=File.open(outfile,'a')
manufacturers_doc.css('select[name="ktlg_01_mrksl"] option').each do |manufacturer|
 # puts manufacturer.inspect
 # next
  manufacturer_id = manufacturer['value'].to_i
  unless manufacturer_id.zero?
    manufacturer_title = manufacturer.content.strip.titleize
#    next if already_parsed[manufacturer_title]
    unless already_parsed[manufacturer_title]
      already_parsed[manufacturer_title] = {}
      puts "#{manufacturer_title}".lightcyan
      $outputfile.write "#{manufacturer_title}\n"
    else
      puts "already parsed, pass all manufacturer production: ".cyan+"#{manufacturer_title}"
#      next
    end
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
        date_str = model_data.last.strip.delete_live_breakes.delete_nbsp
        begin
          model_years = DateParser::normalize_range(date_str)
        rescue Exception => e
          puts "While parsing date interval #{date_str} in [#{model_title}] was thrown error: #{e}".red.bg_gray
          raise e
        end
        if already_parsed[manufacturer_title][model_title].empty?
          already_parsed[manufacturer_title][model_title] = {serie: model_title, life_time: model_years.to_s.gsub(/[\]\[]/,''), models: []}
          puts "  #{model_title}|#{model_years}".lightyellow
          $outputfile.write "  #{model_title}|#{model_years}\n"
        else
          puts "  series #{model_title} already parsed, pass them...".yellow
          next
        end
        modifications_url = "#{mann_url}&ktlg_01_fzart=1&ktlg_01_fzkat=0&ktlg_01_mrksl=#{manufacturer_id}&ktlg_01_mdrsl=#{model_id}&ktlg_c001_flag=1"

        begin
          sleep 2
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
              begin
                cells[9] = DateParser::normalize_range(cells[9]) if cells[9] # Parsing dates
              rescue Exception => e
                puts "While parsing date interval #{cells[9]} in [#{cells.inspect}] was thrown error: #{e}".red.bg_gray
                raise e
              end
              info[:modification], info[:engine], info[:watts], info[:horses], info[:production] = cells[1], cells[3], cells[5], cells[7], cells[9]
              puts "    #{info[:modification]}|#{info[:engine]}|#{info[:watts]}|#{info[:horses]}|#{info[:production]}"
              $outputfile.write "    #{info[:modification]}|#{info[:engine]}|#{info[:watts]}|#{info[:horses]}|#{info[:production]}\n"
              already_parsed[manufacturer_title][model_title][:models] << {
                model_name: info[:modification],
                engines: info[:engine],
                power_kw: info[:watts],
                power_hp: info[:horses],
                life_time: info[:production].to_s.gsub(/[\]\[]/,'')
              }
            end
          end
        rescue Nokogiri::SyntaxError => err
          puts "FAIL with error: #{err}, fix problem and delete it string from output file: #{modifications_url}"
          $outputfile.write "FAIL: #{modifications_url}\n"
          # retry
        end
      end
    end
    sleep 2
  end
end

puts already_parsed.to_json
$outputfile.write already_parsed.to_json

$outputfile.close
