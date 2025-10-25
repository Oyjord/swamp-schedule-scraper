require 'json'
require 'open-uri'
require 'time'

ics_url = "https://swamprabbits.com/schedule-all.ics"
json_path = "swamp_schedule.json"
output_path = "swamp_schedule_enriched.json"

# Step 1: Load JSON
games = JSON.parse(File.read(json_path))

# Step 2: Fetch and parse ICS
ics_text = URI.open(ics_url).read
start_times = {}

ics_text.scan(/DTSTART(?:;TZID=[^:]+)?:([0-9T]+)/).flatten.each do |raw|
  dt = Time.strptime(raw, "%Y%m%dT%H%M%S")
  key = dt.strftime("%b. %-d") # e.g. "Oct. 24"
  start_times[key] = dt.iso8601
end

# Step 3: Inject scheduled_start
games.each do |game|
  key = game["date"]
  game["scheduled_start"] = start_times[key] if start_times[key]
end

# Step 4: Write output
File.write(output_path, JSON.pretty_generate(games))
puts "✅ Injected scheduled_start into #{output_path}"
