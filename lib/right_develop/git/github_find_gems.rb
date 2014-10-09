require 'github_api'
require 'pry'
require 'json'

  USER_NAME = "<username>"
  PASSWORD = "<password>"

REPOS_FILE = "sort_by_repo_results.json"
GEMS_FILE = "sort_by_gem_results.json"


# fetch the contents of a file, or returns nil if file not found
def fetch_file(client, repo, filepath)
  Base64.decode64(client.repos.contents.find(repo.owner.login, repo.name, filepath).content)
rescue Github::Error::NotFound =>e
  nil
end

def get_gems_pointing_to_branches(list, rs_only=true)
  gems_at_branch = {}

  list.each do |repo,gems|
    branch_gems = gems.select do |gem,attrs|
      attrs.has_key?("branch") and (attrs["gem_owner"] == "rightscale" or !rs_only)
    end
    branch_gems.each do |k,v|

    end
  end
  gems_at_branch
end

def sort_by_gem(client,list)
  gem_sorted = {}
  list.each do |repo,gems|
    gems.each do |gem,attrs|
      gem_path = attrs["gem_owner"] + "/" + gem
      unless gem_sorted.has_key?(gem_path)
        this_gem = {}
        this_gem["repos"] = []
        this_gem["tags"]  = get_tags(client,attrs["gem_owner"],gem)

        gem_sorted[gem_path] = this_gem
      end

      repo_is_using =
      gem_sorted[gem_path]["repos"].push({
        "name" => repo,
        "uses" => gem_referenced_as(attrs),
        "value" => attrs[gem_referenced_as(attrs)],
        "current_sha" => attrs["revision"]
      })
    end
  end

  add_last_commiter(client,gem_sorted)
  gem_sorted
end

def sort_by_last_commiter(list)
  commiters = {}
  list.each do |gem,data|
    email = data["last_commiter"]
    commiters[email] ||= {}
    commiters[email][gem] = data
  end
  commiters
end

def get_tags(client,owner,repo)
  begin
    tags = client.repos.tags(owner,repo, auto_pagination: true).body
    tag_hash = {}
    tags.each {|t| tag_hash[t["name"]] = t["commit"]["sha"]}
    tag_hash
  rescue Github::Error::NotFound
  end
end

# returns if the gem is being reference by branch or tag ..etc
def gem_referenced_as(gem_attrs)
  posibilities = ["branch","ref","sha","tag"]
  (gem_attrs.keys & posibilities).first
end

def get_results(client)
  results = {}
  # fetch list of all rightscale repositories
  repos = client.repos.list(auto_pagination: true); repos.count

  repos.each do |repo|

    results[repo.name] = {}
    gem_lock = fetch_file(client, repo, "Gemfile.lock")

    if gem_lock

      # Important areas are separated with two newlines
      gems = gem_lock.split("\n\n")

      # We only care about GIT gems
      gems.delete_if {|l| l !~ /^GIT/}

      # GIT tag has outlived its usefulness
      gems.each {|l| l.gsub!(/GIT\n\s*/,"")}

      # dont care about specs
      gems.each {|l| l.gsub!(/\s*specs:.*/m,"")}


      gems.each do |gem|
        fields = gem.split(/\n\s+/)
        vals = {}
        fields.each do |f|
          m = f.match /(\w*):\s*(.*)/
          vals[m[1]] = m[2]
        end

        m = vals['remote'].match(/github.com[:\/]([-\w]*)\/([-\w]*)[(\.git)]?/)
        vals["gem_owner"] = m[1]
        name = m[2]
        results[repo.name][name] = vals

      end

    end
  end
  results.delete_if {|k,v| v.empty?}
end

def read_file(file_name)
  JSON.parse(File.read(file_name))
end

def add_last_commiter(client,list)
  list.each do |gem,data|
    begin
    sha = client.repos.branches(*gem.split("/"), auto_pagination: true).body.select{|c| c["name"] == "master"}.first["commit"]["sha"]
    response = client.repos.commits.get(*gem.split("/"), sha).body
    email = response["commit"]["author"]["email"]
    date  = response["commit"]["author"]["date"]
    rescue => e
      email = nil
    end
    data["last_commiter"] = email
    data["last_commit_date"] = date
  end
end

def login
  Github.new :basic_auth => "#{USER_NAME}:#{PASSWORD}", :org => "rightscale"
end

client ||= false
client ? nil : (client = login) && binding.pry

#results = get_results(client)
#File.open(REPOS_FILE, "w").write(results.to_json)
#
#output = sort_by_gem(client,results)
#File.open(GEMS_FILE, "w").write(output.to_json)
puts "done"
