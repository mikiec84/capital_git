class LocalRepository

  def initialize options
    @options = options
  end

  def slug
    @options["slug"]
  end

  def local_path
    File.expand_path(File.join("..", "tmp", @options["slug"]), File.dirname(__FILE__))
  end

  def remote_url
    @options["path"]
  end

  def branch
    @options["branch"] || nil
  end

  def dir
    @options["dir"] || nil
  end

  def repository
    if @repository.nil?
      begin
        @repository = Rugged::Repository.new(local_path)
      rescue
        @repository = nil
      end
    end
    @repository
  end

  def set_credentials credential
    @credentials = Rugged::Credentials::SshKey.new({
      :username => credential["username"],
      :publickey => File.expand_path(File.join("../config/keys", credential["publickey"]), File.dirname(__FILE__)),
      :privatekey => File.expand_path(File.join("../config/keys", credential["privatekey"]), File.dirname(__FILE__)),
      :passphrase => credential["passphrase"] || nil
    })
  end

  def credentials
    if !@credentials
      if @options["credentials"]
        set_credentials(@options["credentials"])
      else
        @credentials = nil
      end
    end
    @credentials
  end

  def clone!
    if !repository.nil?
      puts "Repository at #{local_path} already exists"
      pull!
      return
    end

    opts = {}
    opts[:branch] = branch if branch # TODO: doesn't seem to work https://github.com/libgit2/rugged/issues/336
    opts[:credentials] = credentials if credentials

    puts "Cloning #{remote_url} into #{local_path}"
    Rugged::Repository.clone_at(remote_url, local_path, opts)
  end

  # TODO: implement this
  def pull!
    raise("Not implemented")
  end

end