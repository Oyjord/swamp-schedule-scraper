require 'open-uri'
require 'nokogiri'
require 'json'

GAME_REPORT_BASE = "https://lscluster.hockeytech.com/game_reports/official-game-report.php?client_code=echl&game_id="

def parse_game_sheet(game_id)
  url = "#{GAME_REPORT_BASE}#{game_id}&lang_id=1"
  html = URI.open(url).read
  doc = Nokogiri::HTML(html)
  debug = ENV["DEBUG"] == "true"

  rows = doc.css('table').find do |table|
    header = table.at_css('tr')
    header && header.text.include?('Goals') && header.text.include?('Assists')
  end&.css('tr')&.drop(1) || []

  puts "🧪 Found #{rows.size} scoring rows" if debug

  if rows.empty?
    File.write("/tmp/debug_#{game_id}.html", html)
    puts "⚠️ No scoring rows found — dumped HTML to /tmp/debug_#{game_id}.html" if debug
  end

  home_goals, away_goals = [], []

  rows.each do |row|
    tds = row.css('td')
    next unless tds.size >= 7

    team = tds[3].text.strip
    scorer = tds[5].text.split('(').first.strip
    assists = tds[6].text.strip
    entry = assists.empty? ? "#{scorer} (unassisted)" : "#{scorer} (#{assists})"

    puts "→ team: #{team.inspect}, scorer: #{scorer.inspect}, assists: #{assists.inspect}, entry: #{entry.inspect}" if debug

    if team == "GVL"
      home_goals << entry
    elsif team
      away_goals << entry
    end
  end

  {
    game_id: game_id.to_i,
    home_score: home_goals.size,
    away_score: away_goals.size,
    home_goals: home_goals,
    away_goals: away_goals,
    game_report_url: url
  }
rescue => e
  puts "⚠️ Failed to parse game sheet for game_id #{game_id}: #{e}"
  nil
end

if ARGV.empty?
  puts "Usage: ruby enrich_game.rb <game_id>"
  exit 1
end

game_id = ARGV[0]
enriched = parse_game_sheet(game_id)
puts JSON.pretty_generate(enriched) if enriched
