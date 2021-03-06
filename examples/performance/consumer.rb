#
# Sample Consumer: 
#   Retrieve all messages from a queue
#

# Allow examples to be run in-place without requiring a gem install
$LOAD_PATH.unshift File.dirname(__FILE__) + '/../../lib'

require 'rubygems'
require 'yaml'
require 'jms'

jms_provider = ARGV[1] || 'actvemq'

# Load Connection parameters from configuration file
config = YAML.load_file(File.join(File.dirname(__FILE__), '..', 'jms.yml'))[jms_provider]
raise "JMS Provider option:#{jms_provider} not found in jms.yml file" unless config

JMS::Connection.session(config) do |session|
  session.consumer(:queue_name => 'ExampleQueue') do |consumer|
    stats = consumer.each(:statistics => true) do |message|
      puts "=================================="
      p message
    end
    puts "STATISTICS :" + stats.inspect
  end
end
