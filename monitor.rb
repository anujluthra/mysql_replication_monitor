#!/usr/bin/ruby

###############################################################
#  MYSQL Replication Monitoring Script
#
# uses heartbeat timestamps to check the replication lag on server being monitored
# and notifies when the lag in beyong the acceptable limit.
# NOTE:
# 1. please make sure that master and slave server are in sync with same time server.
#    eg. ntpdate ntp.ubuntu.com
#
# 2. You will have to setup some sort of deamon on master to update heartbeat timestamp
#    at regular intervals. I suggest mk-heartbeat (see: http://www.maatkit.org/doc/mk-heartbeat.html)
#
# 3. library dependencies: mysql, net/smtp, time
#
# 4. Add it to cron job list to check the lag every {allowed_lag_in_seconds}+ interval
#
# It also attaches the last 100 lines of mysql error log to help you get an idea of whats going wrong.
# @author anuj.luthra@gmail.com

require 'rubygems'
require 'mysql'
require 'time'
require 'net/smtp'
require 'yaml'

def send_email(message, from=@email_configs['sender'], to=@email_configs['recepients'])
  formatted_message = @email_header + message
  Net::SMTP.start(@email_configs['smtp_host'], @email_configs['smtp_port']) do |smtp|
    smtp.send_message formatted_message, from, to
  end
end

def send_sms(message,from=@sms_configs['sender'], to=@sms_configs['recepient'])
  send_email message, from, "#{to}@#{@sms_configs['sms_gateway_domain']}"
end


def read_settings
  configs = YAML::load(File.read('config.yml'))
  @heartbeat_table = configs['heartbeat_table']
  @allowed_lag = configs['allowed_lag'].to_i
  @server_name = configs['server_name']
  @email_configs = configs['email_configs']
  @sms_configs = configs['sms_configs']
  @db_configs = configs['databases']
end

def do_check(db_config)
  begin
    ################################################
    # Connect to database and fetch latest heartbeat
    db = Mysql.real_connect(db_config['host'], db_config['user'], db_config['password'], db_config['database'], db_config['port'])
    query = "select ts from #{@heartbeat_table}"
    latest_heartbeat = Time.parse(db.query(query).fetch_row.first)
    current_server_time = Time.now

    # Compare timestamps and notify if necessary
    if (current_server_time - @allowed_lag) > latest_heartbeat
      puts 'lag detected...'

      @email_header = gen_email_header(db_config)

      if !@email_configs.nil?
        puts 'sending email alert...'
        send_email email_message(latest_heartbeat, current_server_time, db_config)
      end

      if !@sms_configs.nil?
        puts 'sending sms alert...'
        short_message = "fantasea replication is lagging on #{@server_name}"
        send_sms short_message
      end

    end

  rescue Exception => e
    message = "Error  ==>  #{e.message}"
    puts message
    send_email message
  ensure
     # disconnect from server
     db.close if db
  end

end



def start
  read_settings
  @db_configs.each_pair do |db_name, db_settings|
    puts "Checking replication status for #{db_name}"
    do_check(db_settings)
  end
end


def gen_email_header(db_config)
  <<-EOH
From: Replication Monitor
Subject: Replication lag on #{@server_name} for #{db_config['database']}

  EOH
end


def email_message(latest_heartbeat, current_server_time, db_config)

  error_log_last_100_lines = `tail -n20 #{db_config['error_log']}`
  
  <<END_OF_MESSAGE
Last Heartbeat recieved via replication : #{latest_heartbeat}
The current time on replication server  : #{current_server_time}

Replication is lagging for more than the allowed limit of #{@allowed_lag} seconds.
Please check the replication server immidiately.

MYSQL ERROR OUTPUT (located at #{db_config['error_log']})
======================================================
#{error_log_last_100_lines}

END_OF_MESSAGE

end


start

