#!/usr/bin/env ruby

#--
# Copyright (c) 2014 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale, Inc. and
# the licensee.
#++


require 'github_api'
require 'octokit'
require 'jira'
require 'mechanize'
require 'csv'
require 'io/console'
require 'spinning_cursor'
require 'encryptor'
require 'yaml'
require 'optparse'
require 'net/http'


#
# Usage:
# ./show_product_changes.rb
# use -h flag for list of flags
# use -r flag for a single repo list
# any stored credentials are encrypted and stored in ~/.rs_product_config
#
module ProductChecker

  COMMAND = "show_product_changes.rb"

  GITHUB_MAX_LOGIN_ATTEMPTS = 3

  # For stuff that comes up regularly and is likely to be incorrectly flagged as a JIRA ID
  JIRA_BLACKLIST_IDS = ["US-3", "US-4"]


  class GithubAuthException < Exception
  end

  class AcunoteAuthException < Exception
  end

  class JiraAuthException < Exception
  end


  class Scraper

    attr_accessor :github_username, :github_access_token
    attr_accessor :acunote_username, :acunote_password
    attr_accessor :jira_username, :jira_password
    attr_accessor :product, :single_repo
    attr_accessor :base_branch, :head_branch
    attr_accessor :repos_to_check


    def initialize
      @github_username = nil
      @github_access_token = nil
      @acunote_username = nil
      @acunote_password = nil
      @jira_username = nil
      @jira_password = nil
      @product = nil
      @single_repo = nil
      @base_branch = nil
      @head_branch = nil

      @products_to_repos = {
          "CM"  => ["right_site", "library", "right_api"],
          "CA"  => ["cloud_analytics"],
          "SS"  => []
      }

      @repos_to_check = []
    end


    def products; @products_to_repos.keys; end
    def repos(product); @products_to_repos[product]; end


    #
    # GitHub
    #

    #
    # For access to GitHub, we use an access token, rather than basic username/password authentication.
    # The reasoning behind this is that GitHub supports 2-factor authentication, so the access token method
    # is the only one that can support this (except for OAuth)
    #

    def connect_to_github
      get_github_credentials if @github_username.blank? || @github_access_token.blank?
      retries = 0
      until connected_to_github? || retries >= GITHUB_MAX_LOGIN_ATTEMPTS
        @octokit = Octokit::Client.new(:login => @github_username, :access_token => @github_access_token)
        retries += 1
      end
      raise GithubAuthException.new("User could not be authenticated") unless connected_to_github?
      puts "GitHub Authentication Successful"
      true
    end

    def get_github_credentials
      puts "Please enter a Github Username:"
      @github_username = STDIN.gets.chomp
      puts "The next step will require a security token from GitHub"
      puts "To obtain this token, complete the following steps"
      puts "  1) Open GitHub in your web browser"
      puts "  2) Click on the Settings cog in the top-right hand corner"
      puts "  3) Select the 'Applications' tab"
      puts "  4) Under 'Personal Access Tokens', select 'Generate new token'"
      puts "  5) Only the 'repo' permission is required"
      puts "  NB: This token will only be shown once, so please store is somewhere safe, such as LastPass"
      puts "Please enter a GitHub Access Token:"
      @github_access_token = STDIN.gets.chomp
    end

    def connected_to_github?
      @octokit.present? && @octokit.user_authenticated?
    end

    def is_repo?(repo_name)
      @octokit.repository?("rightscale/#{repo_name}")
    end

    def get_repo(repo_name)
      @octokit.repository("rightscale/#{repo_name}")
    end

    def validate_repo_names
      valid_repo_names = []

      @repos_to_check.each do |name|
        unless is_repo?(name)
          puts "Could not obtain repository: #{name}"
          next
        end
        begin
          @octokit.commit("rightscale/#{name}", @base_branch)
        rescue => e
          puts "ERR: #{@base_branch} could not be found in #{name}"
          next
        end
        begin
          @octokit.commit("rightscale/#{name}", @head_branch)
        rescue => e
          puts "ERR: #{@head_branch} could not be found in #{name}"
          next
        end
        valid_repo_names << name
      end

      @repos_to_check = valid_repo_names
    end


    #
    # Returns an array of GitHub Repositoris to check for diffs between two branches.
    #
    def populate_repos_to_check
      if @single_repo.present?
        puts "single_repo is #{@single_repo}"
        @repos_to_check = [@single_repo]
      else
        until @product.present?
          puts "Please pick a product:"
          products.each_with_index do |p, index|
            puts "#{index + 1}.  #{p}\t[#{repos(p).join(", ")}]"
          end
          input = (STDIN.gets.chomp.to_i) - 1
          if (input >= 0 && input < products.length)
            @product = products[input]
          else
            puts "Incorrect product selection - please try again"
          end
        end
        @repos_to_check = repos(@product)
      end
      @repos_to_check
    end

    def get_branches
      puts "Please enter a base branch name (the older branch, eg: 'staging' or 'releaseX.Y'):"
      @base_branch = STDIN.gets.chomp
      puts "Please enter a head branch name (the newer branch, eg: 'master'):"
      @head_branch = STDIN.gets.chomp
      [@base_branch, @head_branch]
    end


    #
    # JIRA
    #

    def connect_to_jira
      return @jira unless @jira.blank?
      get_jira_credentials if @jira_username.blank? || @jira_password.blank?
      options = {
        :username     => @jira_username,
        :password     => @jira_password,
        :site         => "https://bookiee.rightscale.com/",
        :auth_type    => :basic,
        :context_path => ""
      }
      @jira = JIRA::Client.new(options)
    end

    def get_jira_credentials
      puts "Please enter an Jira username"
      @jira_username = STDIN.gets.chomp
      puts "Please enter an Jira password"
      @jira_password = STDIN.noecho(&:gets).chomp
    end

    def get_jira_story_name_for_id(jira_id)
      connect_to_jira
      begin
        issue = @jira.Issue.find(jira_id)
        return issue.summary
      rescue
        puts "Could not find issue for key #{jira_id}"
        return nil
      end
    end

    def get_jira_story_names_for_ids(jira_ids)
      results = jira_ids.inject({}) do |hash, jira_id|
        summary = get_jira_story_name_for_id(jira_id)
        hash[jira_id] = summary unless summary.blank?
        hash
      end
      results
    end

    def print_jira_story_names(task_ids)
      puts "\n"
      get_jira_story_names_for_ids(task_ids).each do |key, value|
        puts "\n\t#{key} - #{value.gsub(/\n/, "\n\t\t")}\n"
      end
      puts "\n"
    end


    #
    # Acunote
    #

    def connect_to_acunote
      get_acunote_credentials if @acunote_username.blank? || @acunote_password.blank?
      begin
        @mech ||= Mechanize.new
        login_page = @mech.get("https://rightscale.acunote.com/login")
        form = login_page.forms.first
        form["login[username]"] = @acunote_username
        form["login[password]"] = @acunote_password
        dest_page = form.submit(form.buttons.first)
        @mech.cookie_jar.save_as(".acunote.session")
      rescue
        fail("AN Login Failure")
      end
    end

    def get_acunote_credentials
      puts "Please enter an Acunote username"
      @acunote_username = STDIN.gets.chomp
      puts "Please enter an Acunote password"
      @acunote_password = STDIN.noecho(&:gets).chomp
    end

    def get_acunote_story_names_for_ids(acunote_ids)
      response = @mech.get("https://rightscale.acunote.com/projects/2091/tasks/export?selected=#{acunote_ids.join(",")}")
      csv_array = CSV.parse(response.body)
      stories = {}
      csv_array.shift #remove headers
      csv_array.each do |entry|
        stories[entry[1]] = entry[2]
      end
      return stories
    end

    def print_acunote_story_names(task_ids)
      puts "\n"
      get_acunote_story_names_for_ids(task_ids).each do |key, value|
        puts "\n\t#{key} - #{value.gsub(/\n/, "\n\t\t")}\n"
      end
      puts "\n"
    end



    #
    # scrape github commits for jira and AN task IDs
    #
    def get_task_ids_for_repo(repo)
      comparison = @octokit.compare("rightscale/#{repo}", @base_branch, @head_branch)
      acunote_ids = []
      jira_ids = []
      comparison.commits.each do |record|
        msg_str = record.commit.message
        acunote_id = msg_str.scan( /acu[0-9]+/)
        if(acunote_id.length > 0)
          acunote_id = acunote_id[0]
          acunote_id = acunote_id[3..-1]
          acunote_ids.push(acunote_id)
        end
        jira_id = msg_str.scan(/[A-Za-z]+-[0-9]+/)
        if(jira_id.length > 0)
          jira_ids.push(*jira_id)
        end
      end
      #clear duplicates
      acunote_ids.uniq!
      jira_ids.uniq!
      jira_ids -= JIRA_BLACKLIST_IDS
      return {:acunote => acunote_ids, :jira => jira_ids}
    end


    #
    # Deal with Credentials for GitHub, Jira, and Acunote
    #

    def encrypt(key, value)
      # technique from http://datacatalyst.blogspot.co.uk/2013/09/how-to-store-encrypted-passwords-in.html
      Base64.encode64(Encryptor.encrypt(value, :key => key, :algorithm => 'aes-256-ecb')).force_encoding('UTF-8')
    end

    def decrypt(key, value)
      return nil if value.blank?
      Encryptor.decrypt(Base64.decode64(value.force_encoding('ASCII-8BIT')), :key => key, :algorithm => 'aes-256-ecb')
    end

    def populate_credentials

      # get creds from a file stored locally
      if File.file?(ENV['HOME']+'/.rs_product_config')
        user_settings = YAML.load_file(ENV['HOME']+'/.rs_product_config')

        puts "Stored credentials found - please enter your master password."
        puts "If you cannot remember your password, please run './show_product_changes.rb --reset'"
        puts "Please note that this will result in you having to re-enter your credentials"
        master_password = STDIN.noecho(&:gets).chomp

        if user_settings.present?
          if user_settings[:github].present?
            @github_username      = user_settings[:github][:username]
            @github_access_token  = decrypt(master_password, user_settings[:github][:access_token])
          end
          if user_settings[:acunote].present?
            @acunote_username = user_settings[:acunote][:username]
            @acunote_password = decrypt(master_password, user_settings[:acunote][:password])
          end
          if user_settings[:jira].present?
            @jira_username = user_settings[:jira][:username]
            @jira_password = decrypt(master_password, user_settings[:jira][:password])
          end
        end
      end

      # these will ask user for creds if they were not populated here
      connect_to_github
      connect_to_jira
      connect_to_acunote

      true
    end

    def is_password_file_complete?
      return false unless File.file?(ENV['HOME']+'/.rs_product_config')
      user_settings = YAML.load_file(ENV['HOME']+'/.rs_product_config')
      return false if user_settings.blank?
      return false if user_settings[:github].blank?
      return false if user_settings[:github][:username].blank?
      return false if user_settings[:github][:access_token].blank?
      return false if user_settings[:acunote].blank?
      return false if user_settings[:acunote][:username].blank?
      return false if user_settings[:acunote][:password].blank?
      return false if user_settings[:jira].blank?
      return false if user_settings[:jira][:username].blank?
      return false if user_settings[:jira][:password].blank?
      true
    end

    def ask_for_password_save
      return if File.file?(ENV['HOME']+'/.rs_product_config')
      valid_response = false
      resp = ""
      while !valid_response
        puts "Do you wish to save the credentials for next time (Y/n)"
        resp = STDIN.gets.chomp.downcase
        valid_response = true if ["", "y", "n"].include?(resp)
      end
      if ["", "y"].include?(resp)
        puts "Please enter a master password"
        master_password = STDIN.noecho(&:gets).chomp
        File.open(ENV['HOME']+'/.rs_product_config', "w") do |file|
          user_settings = {
              :github => {
                  :username     => @github_username,
                  :access_token => encrypt(master_password, @github_access_token)
              },
              :jira => {
                  :username => @jira_username,
                  :password => nil
              },
              :acunote => {
                  :username => @acunote_username,
                  :password => nil
              }
          }

          if @jira_password.present?
            user_settings[:jira][:password] = encrypt(master_password, @jira_password)
          end

          if @acunote_password.present?
            user_settings[:acunote][:password] = encrypt(master_password, @acunote_password)
          end

          file.write user_settings.to_yaml
        end
      end
    end


    def reset_config
      if File.file?(ENV['HOME']+'/.rs_product_config')
        File.delete(ENV['HOME']+'/.rs_product_config')
      end
    end


    def print_task_descriptions(task_type, task_ids)
      raise "Invalid task type '#{task_type}'." unless [:jira, :acunote].include?(task_type)
      if task_ids[task_type].present?
        SpinningCursor.run do
          banner "Retrieving story names from #{task_type.to_s.capitalize} - please be patient"
          type :dots
        end
        method = "print_#{task_type}_story_names".to_sym
        send(method, task_ids[task_type])
        SpinningCursor.stop
      else
        puts "There are no #{task_type.to_s.capitalize} stories."
      end
    end


    def parse_options
      opt_parser = OptionParser.new do |opt|
        opt.banner = "Usage: #{COMMAND}"
        opt.on('-h', '--help', 'Show help') do
          puts opt_parser
          exit
        end
        opt.on('-r', '--repo repo', 'Run against a single repo' ) do |repo|
          @single_repo = repo
        end
        opt.on('--reset', "Resets saved settings") do
          reset_config
          exit
        end
        opt.on('-v', '--version', 'show version') do
          sha = `git rev-parse HEAD`
          puts "Rightscale product update checker - version #{sha}"
          exit
        end
      end
      opt_parser.parse!
    end


    def run
      parse_options
      puts "\nRightScale Product Update Checker\n\n"
      populate_repos_to_check
      puts "\n"
      populate_credentials
      puts "\n"
      get_branches
      puts "\n"
      validate_repo_names
      puts "\n"

      @repos_to_check.each do |repo_name|
        task_ids = get_task_ids_for_repo(repo_name)
        puts "\n\n"
        puts "".ljust(3*repo_name.size, "-")
        puts "".ljust(1*repo_name.size, " ") + repo_name
        puts "".ljust(3*repo_name.size, "-")
        puts "\n\n"
        print_task_descriptions(:jira, task_ids)
        puts "\n\n"
        print_task_descriptions(:acunote, task_ids)
        puts "\n\n"
      end

      ask_for_password_save unless is_password_file_complete?
    end
  end
end


#
# Execution Starting Point
#
if __FILE__ == $0
  scraper = ProductChecker::Scraper.new
  scraper.run
end
