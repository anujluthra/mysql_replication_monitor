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

# db settings
DB_USER = 'user'
DB_PASS = 'pwd'
DB_PORT = 3306 
DB_HOST = '127.0.0.1'
DB_NAME = 'db_production'
DB_HEARTBEAT_TABLE = 'heartbeat'
ALLOWED_LAG_IN_SECONDS = 120
DB_ERROR_LOG = '/absolute/path/to/error.log'
SERVER_NAME = 'SLAVE-1'

# mail settings
SMTP_HOST = 'mail.localhost'
SMTP_PORT = 25
SENDER    = 'user@localhost'
SUBJECT   = "Replication for #{DB_NAME} is lagging more than allowed limit on #{SERVER_NAME}" 
NOTIFICATION_RECEPIENTS = 'concerned@localhost'

def send_email(message, from=SENDER, to=NOTIFICATION_RECEPIENTS)
  Net::SMTP.start(SMTP_HOST, SMTP_PORT) do |smtp|
    smtp.send_message message, from, to
  end
end

db = Mysql.real_connect(DB_HOST, DB_USER, DB_PASS, DB_NAME, DB_PORT)
latest_heartbeat = Time.parse(db.query("select ts from #{DB_HEARTBEAT_TABLE}").fetch_row.first)
current_server_time = Time.now


if (current_server_time - ALLOWED_LAG_IN_SECOND) > latest_heartbeat
  # replication is lagging so send email
  error_log_last_100_lines = `tail -n100 #{DB_ERROR_LOG}`
  message = <<END_OF_MESSAGE
From: Replication Monitor
Subject: #{SUBJECT}

Last Heartbeat recieved via replication : #{latest_heartbeat}
The current time on replication server  : #{current_server_time}

Replication is lagging more than the allowed limit of #{ALLOWED_LAG_IN_SECONDS} seconds. Please check the replication server immidiately.

MYSQL ERROR OUTPUT (located at #{DB_ERROR_LOG})
======================================================
#{error_log_last_100_lines}

END_OF_MESSAGE

  send_email message
end

