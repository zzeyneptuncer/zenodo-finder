# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "json"
require "net/http"
require "time"
require "uri"
require "sinatra/base"

INDEX_TEMPLATE = <<~'ERB'
  <!doctype html>
  <html lang="tr">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Veri Seti Bulucu</title>
      <style>
        * { box-sizing: border-box; }
        body { margin: 0; background: #f4f7fb; color: #1f2937; font-family: Arial, sans-serif; }
        main { max-width: 920px; margin: 40px auto; padding: 32px; background: #fff; border-radius: 12px; }
        h1 { margin-top: 0; }
        form { display: grid; grid-template-columns: 1fr 180px 110px auto; gap: 10px; align-items: end; }
        label { font-weight: bold; }
        input, select, button { height: 40px; padding: 8px; border: 1px solid #cbd5e1; border-radius: 6px; }
        button { background: #1d4ed8; color: white; border: 0; cursor: pointer; }
        article { display: flex; gap: 14px; margin: 14px 0; padding: 16px; background: #f8fafc; border-left: 4px solid #1d4ed8; }
        article span { font-weight: bold; color: #1d4ed8; }
        h3 { margin: 0; } p { line-height: 1.5; } .error { color: #b91c1c; }
        @media (max-width: 700px) { form { grid-template-columns: 1fr; } }
      </style>
    </head>
    <body>
      <main>
        <h1>Zenodo Veri Seti Bulucu</h1>
        <p>Zenodo kayıtlarını konu ve veri türüne göre ara.</p>
        <form method="get">
          <label for="query">Konu</label>
          <input id="query" name="query" value="<%= @query %>" placeholder="Örn: drone, tarım, accelerometer" required>
          <label for="data_type">Veri türü</label>
          <select id="data_type" name="data_type">
            <option value="">Tümü</option>
            <% ["Görüntü", "Ses", "Sensör"].each do |type| %>
              <option value="<%= type %>" <%= "selected" if @data_type == type %>><%= type %></option>
            <% end %>
          </select>
          <label for="size">Sonuç sayısı</label>
          <input id="size" name="size" type="number" min="1" max="25" value="<%= @size %>">
          <button type="submit">Ara</button>
        </form>
        <% if @error %><p class="error"><%= @error %></p><% end %>
        <% unless @query.empty? || @error %>
          <h2><%= @results.length %> sonuç bulundu</h2>
          <% if @results.empty? %><p>Başka bir konu veya veri türü dene.</p><% end %>
          <% @results.each_with_index do |record, index| %>
            <article>
              <span><%= index + 1 %></span>
              <div>
                <h3><a href="<%= record_link(record) %>" target="_blank" rel="noopener"><%= record_title(record) %></a></h3>
                <p><%= record_description(record) %></p>
                <small>Dosya boyutu: <%= record_size(record) %></small>
              </div>
            </article>
          <% end %>
        <% end %>
      </main>
    </body>
  </html>
ERB

class ZenodoClient
  API_URL = "https://zenodo.org/api/records"

  TYPE_KEYWORDS = {
    "görüntü" => %w[image imagery visual vision photo photograph video],
    "ses" => %w[audio sound acoustic speech music],
    "sensör" => %w[sensor sensing accelerometer gyroscope imu telemetry]
  }.freeze

  def search(query:, data_type: nil, size: 10)
    uri = URI(API_URL)
    uri.query = URI.encode_www_form(q: query, size: [[size.to_i, 1].max, 25].min, sort: "bestmatch")
    response = Net::HTTP.get_response(uri)
    raise "Zenodo isteği başarısız oldu: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    records = JSON.parse(response.body).fetch("hits", {}).fetch("hits", [])
    data_type.to_s.empty? ? records : filter_by_type(records, data_type)
  end

  def filter_by_type(records, data_type)
    keywords = TYPE_KEYWORDS.fetch(data_type.downcase, [data_type.downcase])
    records.select do |record|
      metadata = record.fetch("metadata", {})
      text = [metadata["title"], metadata["description"], metadata["keywords"]].flatten.compact.join(" ").downcase
      keywords.any? { |keyword| text.include?(keyword) }
    end
  end
end

class DatasetFinderApp < Sinatra::Base
  get "/" do
    @query = params.fetch("query", "").strip
    @data_type = params.fetch("data_type", "")
    @size = [[params.fetch("size", "10").to_i, 1].max, 25].min
    @results = []

    unless @query.empty?
      @results = ZenodoClient.new.search(query: @query, data_type: @data_type, size: @size)
      write_log("arama=#{@query} | tür=#{@data_type.empty? ? "yok" : @data_type} | sonuç=#{@results.length}")
    end

    erb INDEX_TEMPLATE
  rescue StandardError => error
    @error = error.message
    erb INDEX_TEMPLATE
  end

  helpers do
    def record_link(record)
      record.dig("links", "html") || "https://zenodo.org/records/#{record["id"]}"
    end

    def record_title(record)
      record.dig("metadata", "title") || "Başlıksız kayıt"
    end

    def record_description(record)
      text = record.dig("metadata", "description").to_s.gsub(/<[^>]*>/, " ").gsub(/\s+/, " ").strip
      text.length > 240 ? "#{text[0, 240]}..." : text
    end

    def record_size(record)
      bytes = record.fetch("files", []).sum { |file| file.fetch("size", 0) }
      return "Belirtilmemiş" if bytes.zero?

      "#{(bytes / 1024.0 / 1024.0).round(2)} MB"
    end

    def write_log(message)
      File.open("zenodo_search.log", "a", encoding: "UTF-8") do |log|
        log.puts "#{Time.now.iso8601} | #{message}"
      end
    end
  end

  run! if app_file == $PROGRAM_NAME
end
