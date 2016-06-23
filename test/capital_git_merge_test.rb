require 'test_helper'
require 'tmpdir'
require 'json'

class CapitalGitHeadMergeTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos") # will have the bare fixture repo
    @tmp_path2 = Dir.mktmpdir("capital-git-test-repos") # will have the clone of the bare fixture repo
   
    @bare_repo = Rugged::Repository.clone_at(
          File.join(File.expand_path("fixtures", File.dirname(__FILE__)), "testrepo.git"),
          File.join(@tmp_path, "bare-testrepo.git"),
          :bare => true
        )
    @bare_repo.remotes['origin'].fetch("+refs/*:refs/*")
    @database = CapitalGit::Database.new({:local_path => @tmp_path2})
    @database.committer = {"email"=>"albert.sun@nytimes.com", "name"=>"albert_capital_git dev"}
    @repo = @database.connect("#{@tmp_path}/bare-testrepo.git", :default_branch => "master")
  end

  # repository.branches.each {|b| puts b.target.author} # target is a commit or another reference
  # 
  # mybranches = repository.branches.select {|b| b.target.author[:email] == "albert.sun@nytimes.com" && !b.remote?}}
  # 

  # tags can have annotations (?)
  # perhaps use that to store data about how it should be merged/was created?
  # instead of branches which can't have annotations

  # use a user's unique identifier as their branch identifier?
  # then it's like everyone has their own working copy
  # but one person can't have multiple different proposed edits to be handled separately
  # ... maybe there should be both
  # ... each person should have their own working copy branch
  # ... AND each proposed edit is it's own branch

  # repo.propose
  # proposal_id = @repo.propose("README", "just a thought", :message => "a proposed edit") # branch
  #
  # array_of_proposals = @repo.get_proposals()
  # array_of_proposals = @repo.get_proposals("README") 
  # proposal_obj = @repo.get_proposal(proposal_id)
  # @repo.accept_proposal(proposal_id) # merge
  # 
  # @repo.get_user_proposals(name_or_email)

  # how to manage branches?
  # repository.branches[] # repository.branches.each {|b| ... }

  # merge analysis
  # http://www.rubydoc.info/gems/rugged/Rugged/Repository#merge_analysis-instance_method
  # :normal, :up_to_date, :fastforward, :unborn

  def test_ff_merge
    branch_name = @repo.create_branch[:name]
    assert @repo.write("README", "brand new readme\n", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "first commit on new branch"
      })
    refute_equal @repo.read_all, @repo.read_all(branch: branch_name)

    last_commit_sha = @repo.log(branch: branch_name)[0][:commit]
    refute_equal last_commit_sha, @repo.log[0][:commit]

    merge_result = @repo.merge_branch(branch_name)
    refute_nil merge_result

    assert_equal last_commit_sha, merge_result[:commit]
    assert_equal last_commit_sha, @repo.log[0][:commit]
  end

  def test_merge_preview
    merge_base = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich"
      })
    branch_name = @repo.create_branch[:name]
    orig_head = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on master (add Bacon)"
      })
    merge_head = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (normal mustard)"
      })

    # merge preview shows the diff between merge_base and merge_head
    diff_val = {:commits => [merge_base[:commit], merge_head[:commit]], :files_changed=>1, :additions=>1, :deletions=>1, :changes=>{:modified=>[{:old_path=>"sandwich.txt", :new_path=>"sandwich.txt", :patch=>"diff --git a/sandwich.txt b/sandwich.txt\nindex c76e978..d41fe58 100644\n--- a/sandwich.txt\n+++ b/sandwich.txt\n@@ -3,5 +3,5 @@ Mayonnaise\n Lettuce\n Tomato\n Provolone\n-Creole Mustard\n+Mustard\n Bottom piece of bread\n\\ No newline at end of file\n", :additions=>1, :deletions=>1}]}}
    merge_preview_diff = @repo.merge_preview(branch_name)
    regular_diff = @repo.diff(merge_base[:commit], merge_head[:commit])

    assert_equal regular_diff, merge_preview_diff
    assert_equal diff_val, merge_preview_diff
  end

  def test_auto_merge
    merge_base_sha = @repo.log[0][:commit]

    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich"
      })
    assert_equal "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", @repo.read("sandwich.txt")[:value], "sanity check"

    branch_name = @repo.create_branch[:name]
    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on master (add Bacon)"
      })
    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (normal mustard)"
      })
    

    head_commit_sha = @repo.log[0][:commit]
    branch_commit_sha = @repo.log(branch: branch_name)[0][:commit]

    refute_equal @repo.read_all, @repo.read_all(branch: branch_name)
    refute_equal @repo.log[0][:commit], @repo.log(branch: branch_name)[0][:commit]
    refute_equal merge_base_sha, @repo.log[0][:commit]

    merge_result = @repo.merge_branch(branch_name, message: "This is an automerge!")
    refute_nil merge_result

    # @repo.log(limit: 3).each {|c| puts c.inspect}
    # puts @repo.read_all
    assert_equal "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", @repo.read("sandwich.txt")[:value]

    assert_equal @repo.log[0][:commit], merge_result[:commit]
    refute_equal @repo.log[0][:commit], head_commit_sha
    refute_equal @repo.log[0][:commit], branch_commit_sha
    assert_equal branch_commit_sha, @repo.log(branch: branch_name)[0][:commit]
    assert_equal @repo.log[1][:commit], branch_commit_sha
    assert_equal @repo.log[2][:commit], head_commit_sha
  end

  def test_conflict_merge
    merge_base_sha = @repo.log[0][:commit]

    merge_base = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich"
      })
    assert_equal "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", @repo.read("sandwich.txt")[:value], "sanity check"

    branch_name = @repo.create_branch[:name]
    orig_head = @repo.write("sandwich.txt", "Top piece of bread\nAvocado\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on master (add Bacon)"
      })
    merge_head = @repo.write("sandwich.txt", "Top piece of bread\nKetchup\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (normal mustard)"
      })

    head_commit_sha = @repo.log[0][:commit]
    branch_commit_sha = @repo.log(branch: branch_name)[0][:commit]

    refute_equal @repo.read_all, @repo.read_all(branch: branch_name)
    refute_equal @repo.log[0][:commit], @repo.log(branch: branch_name)[0][:commit]
    refute_equal merge_base_sha, @repo.log[0][:commit]

    merge_result = @repo.merge_branch(branch_name, message: "attempting an automerge!")
    # puts merge_result
    refute_nil merge_result
    assert_equal false, merge_result[:success]
    assert_equal [:success, :orig_head, :merge_head, :merge_base, :conflicts].sort, merge_result.keys.sort
    assert_equal merge_base, merge_result[:merge_base]
    assert_equal orig_head, merge_result[:orig_head]
    assert_equal merge_head, merge_result[:merge_head]
    assert_equal 1, merge_result[:conflicts].count
    assert_equal [:merge_file, :path, :ancestor, :ours, :theirs].sort, merge_result[:conflicts][0].keys.sort
  end

  def test_write_merge
    skip
  end


  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
    FileUtils.remove_entry_secure(@tmp_path2)
  end
end