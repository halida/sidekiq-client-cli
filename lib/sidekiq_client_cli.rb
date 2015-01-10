require 'sidekiq'
require 'cli'
require_relative 'sidekiq_client_cli/version'

class SidekiqClientCLI
  COMMANDS = %w{push}
  DEFAULT_CONFIG_PATH = "config/initializers/sidekiq.rb"

  attr_accessor :settings

  def parse
    @settings = CLI.new do
      option :config_path, :short => :c, :default => DEFAULT_CONFIG_PATH, :description => "Sidekiq client config file path"
      option :queue, :short => :q, :description => "Queue to place job on"
      option :retry, :short => :r, :cast => lambda { |r| SidekiqClientCLI.cast_retry_option(r) }, :description => "Retry option for job"
      argument :command, :description => "'push' to push a job to the queue"
      arguments :command_args, :required => false, :description => "command arguments"
    end.parse! do |settings|
      fail "Invalid command '#{settings.command}'. Available commands: #{COMMANDS.join(',').chomp(',')}" unless COMMANDS.include? settings.command

      if settings.command == "push" && settings.command_args.empty?
        fail "No Worker Classes to push"
      end
    end
  end

  def self.cast_retry_option(retry_option)
    return true if !!retry_option.match(/^(true|t|yes|y)$/i)
    return false if !!retry_option.match(/^(false|f|no|n|0)$/i)
    return retry_option.to_i if !!retry_option.match(/^\d+$/)
  end

  def run
    # load the config file
    load settings.config_path if File.exists?(settings.config_path)

    # set queue or retry if they are not given
    settings.queue ||= Sidekiq.default_worker_options['queue']
    settings.retry = Sidekiq.default_worker_options['retry'] if settings.retry.nil?

    self.send settings.command.to_sym
  end

  # Returns true if all args can be pushed successfully.
  # Returns false if at least one exception occured.
  def push
    settings.command_args.inject(true) do |success, arg|
      push_argument arg
    end
  end

  private

  def push_argument(arg)
    klass, klass_args = parse_task_string(arg)
    jid = Sidekiq::Client.push({ 'class' => klass,
                                 'queue' => settings.queue,
                                 'args'  => klass_args,
                                 'retry' => settings.retry })
    p "Posted #{arg} to queue '#{settings.queue}', Job ID : #{jid}, Retry : #{settings.retry}"
    true
  rescue StandardError => ex
    p "Failed to push to queue : #{ex.message}"
    false
  end


  # pilfered from rake
  # commas within args are not supported
  def parse_task_string(string)
    /^([^\[]+)(?:\[(.*)\])$/ =~ string.to_s

    name           = $1
    remaining_args = $2

    return string, [] unless name
    return name,   [] if     remaining_args.empty?

    args = []

    begin
      /((?:[^\\,]|\\.)*?)\s*(?:,\s*(.*))?$/ =~ remaining_args

      remaining_args = $2
      args << $1.gsub(/\\(.)/, '\1')
    end while remaining_args

    return name, args
  end
end
