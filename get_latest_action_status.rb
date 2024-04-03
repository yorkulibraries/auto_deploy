#!/usr/bin/env ruby

require 'open-uri'
require 'json'

repo = "yorkulibraries/#{ARGV[0]}"
branch = ARGV[1] || 'master'
workflow_name = ARGV[2] || 'Ruby on Rails CI'
u = URI.open("https://api.github.com/repos/#{repo}/actions/runs")
j = JSON.load(u)
j['workflow_runs'].each do | r |
  if r['head_branch'] == branch && r['name'] == workflow_name
    puts "#{r['updated_at']} #{r['conclusion']}"
    break
  end
end

