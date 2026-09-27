# frozen_string_literal: true

require "json"
require "net/http"
require "optparse"
require "time"
require "uri"

API_URL = "https://zenodo.org/api/records"

options = { size: 10 }
OptionParser.new do |parser|
  parser.banner = "Kullanım: ruby zenodo_search.rb --query KONU [seçenekler]"
  parser.on("-q", "--query KONU", "Zenodo arama konusu") { |value| options[:query] = value }
  parser.on("-t", "--type TÜR", "Veri türü filtresi: görüntü, ses, sensör") { |value| options[:type] = value }
  parser.on("-s", "--size N", Integer, "Sonuç sayısı (varsayılan: 10)") { |value| options[:size] = value }
end.parse!

if options[:query].to_s.strip.empty?
  warn "Hata: --query zorunludur. Örnek: ruby zenodo_search.rb --query drone"
  exit 1
end

params = { "q" => options[:query], "size" => [options[:size], 25].min, "sort" => "bestmatch" }
uri = URI(API_URL)
uri.query = URI.encode_www_form(params)

response = Net::HTTP.get_response(uri)
unless response.is_a?(Net::HTTPSuccess)
  warn "Zenodo isteği başarısız oldu: HTTP #{response.code}"
  exit 1
end

records = JSON.parse(response.body).fetch("hits", {}).fetch("hits", [])
if options[:type]
  type = options[:type].downcase
  records = records.select do |record|
    metadata = record.fetch("metadata", {})
    text = [metadata["title"], metadata["description"], metadata["keywords"]].flatten.compact.join(" ").downcase
    text.include?(type)
  end
end

puts "#{records.length} sonuç bulundu."
puts
puts format("%-4s %-70s %s", "No", "Başlık", "Bağlantı")
puts "-" * 120

records.each_with_index do |record, index|
  metadata = record.fetch("metadata", {})
  title = metadata.fetch("title", "Başlıksız").gsub(/\s+/, " ")
  link = record.dig("links", "html") || "https://zenodo.org/records/#{record["id"]}"
  puts format("%-4s %-70s %s", index + 1, title[0, 70], link)
end

File.open("zenodo_search.log", "a", encoding: "UTF-8") do |log|
  log.puts "#{Time.now.iso8601} | arama=#{options[:query]} | tür=#{options[:type] || "yok"} | sonuç=#{records.length}"
end
