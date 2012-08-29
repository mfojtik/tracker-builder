#!/usr/bin/ruby

require 'rubygems'
require_relative './lib/builder.rb'

loop do
  Tracker::Builder.sets.each do |set|
    begin
      build = Tracker::Builder.build!(set['id'])
      if build
        Tracker::Builder.cache_results!(build)
        Tracker::Builder.upload_results!(build)
      end
    rescue
      puts "ERROR!"
    end
  end
  sleep(180)
end
