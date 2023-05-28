require 'tmpdir'
require 'aws-sdk-s3'

class CodePackager
  CmdError = Class.new(StandardError)

  def initialize(repo:, region:, access_key_id:, secret_access_key:, s3_bucket: nil)
    @s3_bucket = s3_bucket
    @repo = repo
    @s3_client = Aws::S3::Client.new(
      region: region,
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
    )
  end

  def call(s3_path:, branch: 'main')
    Dir.mktmpdir do |dir|
      # Clone copy of branch
      code_path = File.join(dir, 'code')
      clone(branch, code_path)

      # Install packages and create zip file
      zip_path = File.join(dir, 'function.zip')
      zip(code_path, zip_path)

      # Upload to S3
      s3 = Aws::S3::Object.new(s3_bucket, s3_path, client: s3_client)
      s3.upload_file(zip_path)
    end

    true
  end

  private

  attr_reader :s3_bucket, :repo, :s3_client

  def clone(branch, code_path)
    run_shell_cmd "git clone -b #{branch} git@github.com:#{repo}.git #{code_path}"
  end

  def zip(code_path, zip_path)
    Bundler.with_original_env do
      Dir.chdir code_path do
        run_shell_cmd("rvm install 2.7")
        run_shell_cmd("rvm use 2.7")
        run_shell_cmd("gem install bundler")
        run_shell_cmd("bundle config set --local path './vendor/bundle'")
        run_shell_cmd("bundle install")
        run_shell_cmd("zip -r #{zip_path} lambda_function.rb Gemfile* *.gemspec vendor lib config")
      end
    end
  end

  def run_shell_cmd(cmd)
    result = system(cmd)
    raise CmdError unless result
  end
end
