################################################################################
#  Copyright 2008, 2009, 2010, 2011  J. Reid Morrison
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
################################################################################

# Module: Java Messaging System (JMS) Interface
module JMS
  # Every JMS session must have at least one Connection instance
  # A Connection instance represents a connection between this client application
  # and the JMS Provider (server/queue manager/broker).
  # A connection is distinct from a Session, in that multiple Sessions can share a
  # single connection. Also, unit of work control (commit/rollback) is performed
  # at the Session level.
  #
  # Since many JRuby applications will only have one connection and one session
  # several convenience methods have been added to support creating both the
  # Session and Connection objects automatically.
  #
  # For Example, to read all messages from a queue and then terminate:
  #  require 'rubygems'
  #  require 'jms'
  #
  #  JMS::Connection.create_session(
  #    :queue_manager=>'REID',   # Should be :q_mgr_name
  #    :host_name=>'localhost',
  #    :channel=>'MY.CLIENT.CHL',
  #    :port=>1414,
  #    :factory => com.ibm.mq.jms.MQQueueConnectionFactory,
  #    :transport_type => com.ibm.mq.jms.JMSC::MQJMS_TP_CLIENT_MQ_TCPIP,
  #    :username => 'mqm'
  #  ) do |session|
  #    session.consumer(:queue_name=>'TEST', :mode=>:input) do |consumer|
  #      if message = consumer.receive_no_wait
  #        puts "Data Received: #{message.data}"
  #      else
  #        puts 'No message available'
  #      end
  #    end
  #  end
  #
  # The above code creates a Connection and then a Session. Once the block completes
  # the session is closed and the Connection disconnected.
  #
  # See: http://download.oracle.com/javaee/6/api/javax/jms/Connection.html
  #
  class Connection
    # Create a connection to the JMS provider, start the connection,
    # call the supplied code block, then close the connection upon completion
    #
    # Returns the result of the supplied block
    def self.start(params = {}, &proc)
      raise "Missing mandatory Block when calling JMS::Connection.start" unless proc
      connection = Connection.new(params)
      connection.start
      begin
        proc.call(connection)
      ensure
        connection.close
      end
    end

    # Connect to a JMS Broker, create a session and call the code block passing in the session
    # Both the Session and Connection are closed on termination of the block
    #
    # Shortcut convenience method to both connect to the broker and create a session
    # Useful when only a single session is required in the current thread
    #
    # Note: It is important that each thread have its own session to support transactions
    def self.session(params = {}, &proc)
      self.start(params) do |connection|
        connection.session(params, &proc)
      end
    end

    # Load the required jar files for this JMS Provider and
    # load JRuby extensions for those classes
    #
    # Rather than copying the JMS jar files into the JRuby lib, load them
    # on demand. JRuby JMS extensions are only loaded once the jar files have been
    # loaded.
    #
    # Can be called multiple times if required, although it would not be performant
    # to do so regularly.
    #
    # Parameter: jar_list is an Array of the path and filenames to jar files
    #                     to load for this JMS Provider
    #
    # Returns nil
    #
    # TODO make this a class method
    def fetch_dependencies(jar_list)
      if jar_list
        jar_list.each do |jar|
          JMS::logger.info "Loading Jar File:#{jar}"
          begin
            require jar
          rescue Exception => exc
            JMS::logger.error "Failed to Load Jar File:#{jar}. #{exc.to_s}"
          end
        end
      end
      require 'jms/message_listener'
      require 'jms/javax_jms_message'
      require 'jms/javax_jms_text_message'
      require 'jms/javax_jms_map_message'
      require 'jms/javax_jms_object_message'
      require 'jms/javax_jms_session'
      require 'jms/javax_jms_message_consumer'
      require 'jms/javax_jms_queue_browser'
    end

    # Create a connection to the JMS provider
    #
    # Note: Connection::start must be called before any consumers will be
    #       able to receive messages
    #
    # In JMS we need to start by obtaining the JMS Factory class that is supplied
    # by the JMS Vendor.
    #
    # There are 3 ways to establish a connection to a JMS Provider
    #   1. Supply the name of the JMS Providers Factory Class
    #   2. Supply an instance of the JMS Provider class itself
    #   3. Use a JNDI lookup to return the JMS Provider Factory class
    # Parameters:
    #   :factory   => String: Name of JMS Provider Factory class
    #              => Class: JMS Provider Factory class itself
    #
    #   :jndi_name    => String: Name of JNDI entry at which the Factory can be found
    #   :jndi_context => Mandatory if jndi lookup is being used, contains details
    #                    on how to connect to JNDI server etc.
    #
    # :factory and :jndi_name are mutually exclusive, both cannot be supplied at the
    # same time. :factory takes precedence over :jndi_name
    #
    # JMS Provider specific properties can be set if the JMS Factory itself
    # has setters for those properties. Some known examples:
    #
    #   For HornetQ
    #    :factory => 'org.hornetq.jms.client.HornetQConnectionFactory',
    #    :discovery_address => '127.0.0.1',
    #    :discovery_port => '5445',
    #    :username => 'guest',
    #    :password => 'guest'
    #
    #   For HornetQ using JNDI lookup technique
    #    :jndi_name => '/ConnectionFactory',
    #    :jndi_context => {
    #      'java.naming.factory.initial' => 'org.jnp.interfaces.NamingContextFactory',
    #      'java.naming.provider.url' => 'jnp://localhost:1099',
    #      'java.naming.factory.url.pkgs' => 'org.jboss.naming:org.jnp.interfaces',
    #      'java.naming.security.principal' => 'guest',
    #      'java.naming.security.credentials' => 'guest'
    #    }
    #
    #   On Java 6, HornetQ needs the following jar files on your CLASSPATH:
    #     hornetq-core-client.jar
    #     netty.jar
    #     hornetq-jms-client.jar
    #     jboss-jms-api.jar
    #     jnp-client.jar
    #
    #   On Java 5, HornetQ needs the following jar files on your CLASSPATH:
    #     hornetq-core-client-java5.jar
    #     netty.jar
    #     hornetq-jms-client-java5.jar
    #     jboss-jms-api.jar
    #     jnp-client.jar
    #
    #   For: WebSphere MQ
    #    :factory => 'com.ibm.mq.jms.MQQueueConnectionFactory',
    #    :queue_manager=>'REID',
    #    :host_name=>'localhost',
    #    :channel=>'MY.CLIENT.CHL',
    #    :port=>1414,
    #    :transport_type => com.ibm.mq.jms.JMSC::MQJMS_TP_CLIENT_MQ_TCPIP,
    #    :username => 'mqm'
    #
    #   For: Active MQ
    #    :factory => 'org.apache.activemq.ActiveMQConnectionFactory',
    #    :broker_url => 'tcp://localhost:61616'
    #
    #   ActiveMQ requires the following jar files on your CLASSPATH
    #
    #   For Oracle AQ 9 Server
    #    :factory => 'JMS::OracleAQConnectionFactory',
    #    :url => 'jdbc:oracle:thin:@hostname:1521:instanceid',
    #    :username => 'aquser',
    #    :password => 'mypassword'
    #
    #   For JBoss, which uses JNDI lookup technique
    #    :jndi_name => 'ConnectionFactory',
    #    :jndi_context => {
    #      'java.naming.factory.initial' => 'org.jnp.interfaces.NamingContextFactory',
    #      'java.naming.provider.url' => 'jnp://localhost:1099'
    #      'java.naming.security.principal' => 'user',
    #      'java.naming.security.credentials' => 'pwd'
    #    }
    #
    #   For Apache Qpid / Redhat Messaging, using Factory class directly
    #    :factory:  org.apache.qpid.client.AMQConnectionFactory
    #    :broker_url: tcp://localhost:5672
    #
    #   For Apache Qpid / Redhat Messaging, via JNDI lookup
    #    :jndi_name => 'local',
    #    :jndi_context => {
    #      'java.naming.factory.initial' => 'org.apache.qpid.jndi.PropertiesFileInitialContextFactory',
    #      'connectionfactory.local' => "amqp://guest:guest@clientid/testpath?brokerlist='tcp://localhost:5672'"
    #    }
    #
    def initialize(params = {})
      # Used by ::on_message
      @sessions = []
      @consumers = []

      # Load Jar files on demand so that they do not need to be in the CLASSPATH
      # of JRuby lib directory
      fetch_dependencies(params[:require_jars])

      connection_factory = nil
      factory = params[:factory]
      if factory
        # If factory is a string, then it is the name of a class, not the class itself
        factory = eval(factory) if factory.respond_to? :to_str
        connection_factory = factory.new
      elsif jndi_name = params[:jndi_name]
        raise "Missing mandatory parameter :jndi_context missing in call to Connection::connect" unless jndi_context = params[:jndi_context]
        jndi = javax.naming.InitialContext.new(java.util.Hashtable.new(jndi_context))
        begin
          connection_factory = jndi.lookup jndi_name
        ensure
          jndi.close
        end
      else
        raise "Missing mandatory parameter :factory or :jndi_name missing in call to Connection::connect"
      end

      JMS::logger.debug "Using Factory: #{connection_factory.java_class}" if connection_factory.respond_to? :java_class
      params.each_pair do |key, val|
        method = key.to_s+'='
        if connection_factory.respond_to? method
          connection_factory.send method, val
          JMS::logger.debug "   #{key} = #{connection_factory.send key}" if connection_factory.respond_to? key.to_sym
        end
      end
      if params[:username]
        @jms_connection = connection_factory.create_connection(params[:username], params[:password])
      else
        @jms_connection = connection_factory.create_connection
      end
    end

    # Start (or restart) delivery of incoming messages over this connection.
    # By default no messages are delivered until this method is called explicitly
    # Delivery of messages to any asynchronous Destination::each() call will only
    # start after Connection::start is called, or Connection.start is used
    def start
      @jms_connection.start
    end

    # Temporarily stop delivery of incoming messages on this connection
    # Useful during a hot code update or other changes that need to be completed
    # without any new messages being processed
    # Call start() to resume receiving messages
    def stop
      @jms_connection.stop
    end

    # Create a session over this connection.
    # It is recommended to create separate sessions for each thread
    # If a block of code is passed in, it will be called and then the session is automatically
    # closed on completion of the code block
    #
    # Parameters:
    #  :transacted => true or false
    #      Determines whether transactions are supported within this session.
    #      I.e. Whether commit or rollback can be called
    #      Default: false
    #  :options => any of the javax.jms.Session constants
    #      Default: javax.jms.Session::AUTO_ACKNOWLEDGE
    #
    def session(params={}, &proc)
      raise "Missing mandatory Block when calling JMS::Connection#session" unless proc
      session = self.create_session(params)
      begin
        proc.call(session)
      ensure
        session.close
      end
    end

    # Create a session over this connection.
    # It is recommended to create separate sessions for each thread
    #
    # Note: Remember to call close on the returned session when it is no longer
    #       needed. Rather use JMS::Connection#session with a block whenever
    #       possible
    #
    # Parameters:
    #  :transacted => true or false
    #      Determines whether transactions are supported within this session.
    #      I.e. Whether commit or rollback can be called
    #      Default: false
    #      Note: :options below is ignored if this value is set to :true
    #  :options => any of the javax.jms.Session constants:
    #     Note: :options is ignored of :transacted => true
    #     javax.jms.Session::AUTO_ACKNOWLEDGE
    #        With this acknowledgment mode, the session automatically acknowledges
    #        a client's receipt of a message either when the session has successfully
    #        returned from a call to receive or when the message listener the session has
    #        called to process the message successfully returns.
    #     javax.jms.Session::CLIENT_ACKNOWLEDGE
    #        With this acknowledgment mode, the client acknowledges a consumed
    #        message by calling the message's acknowledge method.
    #     javax.jms.Session::DUPS_OK_ACKNOWLEDGE
    #        This acknowledgment mode instructs the session to lazily acknowledge
    #        the delivery of messages.
    #     javax.jms.Session::SESSION_TRANSACTED
    #        This value is returned from the method getAcknowledgeMode if the
    #        session is transacted.
    #     Default: javax.jms.Session::AUTO_ACKNOWLEDGE
    #
    def create_session(params={})
      transacted = params[:transacted] || false
      options = params[:options] || javax.jms.Session::AUTO_ACKNOWLEDGE
      @jms_connection.create_session(transacted, options)
    end

    # Close connection with the JMS Provider
    # First close any consumers or sessions that are active as a result of JMS::Connection::on_message
    def close
      @consumers.each {|consumer| consumer.close } if @consumers
      @consumers = []

      @sessions.each {|session| session.close} if @sessions
      @session=[]

      @jms_connection.close if @jms_connection
    end

    # Gets the client identifier for this connection.
    def client_id
      @jms_connection.getClientID
    end

    # Sets the client identifier for this connection.
    def client_id=(client_id)
      @jms_connection.setClientID(client_id)
    end

    # Returns the ExceptionListener object for this connection
    # Returned class implements interface javax.jms.ExceptionListener
    def exception_listener
      @jms_connection.getExceptionListener
    end

    # Sets an exception listener for this connection
    # See ::on_exception to set a Ruby Listener
    # Returns: nil
    def exception_listener=(listener)
      setExceptionListener(listener)
    end

    # Whenever an exception occurs the supplied block is called
    # This is important when Connection::on_message has been used, since
    # failures to the connection would be lost otherwise
    # 
    # For details on the supplied parameter when the block is called, 
    # see: http://download.oracle.com/javaee/6/api/javax/jms/JMSException.html
    # 
    # Example:
    #   connection.on_message do |jms_exception|
    #     puts "JMS Exception has occurred: #{jms_exception}"
    #   end
    #
    # Returns: nil
    def on_exception(&block)
      setExceptionListener(block)
    end

    # Gets the metadata for this connection
    # see: http://download.oracle.com/javaee/6/api/javax/jms/ConnectionMetaData.html
    def meta_data
      @jms_connection.getMetaData
    end

    # Return a string describing the JMS provider and version
    def to_s
      md = @jms_connection.getMetaData
      "JMS::Connection provider: #{md.getJMSProviderName} v#{md.getProviderVersion}, JMS v#{md.getJMSVersion}"
    end

    # TODO: Return a pretty print version of the current JMS Connection
    #    def to_s
    #    end

    # Receive messages in a separate thread when they arrive
    # Allows messages to be recieved in a separate thread. I.e. Asynchronously
    # This method will return to the caller before messages are processed.
    # It is then the callers responsibility to keep the program active so that messages
    # can then be processed.
    #
    # Session Parameters:
    #  :transacted => true or false
    #      Determines whether transactions are supported within this session.
    #      I.e. Whether commit or rollback can be called
    #      Default: false
    #  :options => any of the javax.jms.Session constants
    #      Default: javax.jms.Session::AUTO_ACKNOWLEDGE
    #
    #   :session_count : Number of sessions to create, each with their own consumer which
    #                    in turn will call the supplied Proc.
    #                    Note: The supplied Proc must be thread safe since it will be called
    #                          by several threads at the same time.
    #                          I.e. Don't change instance variables etc. without the
    #                          necessary semaphores etc.
    #                    Default: 1
    #
    # Consumer Parameters:
    #   :queue_name     => String: Name of the Queue to return
    #                  Symbol: :temporary => Create temporary queue
    #                  Mandatory unless :topic_name is supplied
    #     Or,
    #   :topic_name => String: Name of the Topic to write to or subscribe to
    #                  Symbol: :temporary => Create temporary topic
    #                  Mandatory unless :queue_name is supplied
    #     Or,
    #   :destination=> Explicit javaxJms::Destination to use
    #
    #   :selector   => Filter which messages should be returned from the queue
    #                  Default: All messages
    #   :no_local   => Determine whether messages published by its own connection
    #                  should be delivered to it
    #                  Default: false
    #
    #   :statistics Capture statistics on how many messages have been read
    #      true  : This method will capture statistics on the number of messages received
    #              and the time it took to process them.
    #              The timer starts when each() is called and finishes when either the last message was received,
    #              or when Destination::statistics is called. In this case MessageConsumer::statistics
    #              can be called several times during processing without affecting the end time.
    #              Also, the start time and message count is not reset until MessageConsumer::each
    #              is called again with :statistics => true
    #
    #              The statistics gathered are returned when :statistics => true and :async => false
    #
    # Usage: For transacted sessions (the default) the Proc supplied must return
    #        either true or false:
    #          true => The session is committed
    #          false => The session is rolled back
    #          Any Exception => The session is rolled back
    #
    # Note: Also supply connection::on_exception so that connection failures can be handled
    #
    #
    def on_message(params, &proc)
      raise "JMS::Connection must be connected prior to calling JMS::Connection::on_message" unless @sessions && @consumers

      consumer_count = params[:session_count] || 1
      consumer_count.times do
        session = self.create_session(params)
        consumer = session.consumer(params)
        if session.transacted?
          consumer.on_message(params) do |message|
            begin
              proc.call(message) ? session.commit : session.rollback
            rescue => exc
              session.rollback
              throw exc
            end
          end
        else
          consumer.on_message(params, &proc)
        end
        @consumers << consumer
        @sessions << session
      end
    end

    def on_message_statistics
      @consumers.collect{|consumer| consumer.on_message_statistics}
    end

  end

  # Wrapper to support Oracle AQ
  class OracleAQConnectionFactory
    attr_accessor :username, :url
    attr_writer :password

    # Creates a connection per standard JMS 1.1 techniques from the Oracle AQ JMS Interface
    def create_connection
      cf = oracle.jms.AQjmsFactory.getConnectionFactory(@url, java.util.Properties.new)
      if username
        cf.createConnection(@username, @password)
      else
        cf.createConnection()
      end
    end
  end

end
