#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# Copyright:: Copyright (c) 2014 GitLab.com
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

name "gitlab-rails"
version "master"

dependency "ruby"
dependency "bundler"
dependency "libxml2"
dependency "libxslt"
dependency "curl"
dependency "rsync"
dependency "libicu"
dependency "postgresql"

source :git => "https://gitlab.com/gitlab-org/gitlab-ce.git"

env = {
  "LDFLAGS" => "-L#{install_dir}/embedded/lib -I#{install_dir}/embedded/include",
  "CFLAGS" => "-L#{install_dir}/embedded/lib -I#{install_dir}/embedded/include",
  "LD_RUN_PATH" => "#{install_dir}/embedded/lib",
}

build do
  # GitLab assumes it can extract the Git revision of the currently version
  # from the Git repo the code lives in at boot. Because of our rsync later on,
  # this assumption does not hold. The sed command below patches the GitLab
  # source code to include the Git revision of the code included in the omnibus
  # build.
  command "sed -i \"s/.*REVISION.*/REVISION = '$(git log --pretty=format:'%h' -n 1)'/\" config/initializers/2_app.rb"

  bundle "install --without mysql development test --path=#{install_dir}/embedded/service/gem", :env => env

  # In order to precompile the assets, we need to get to a state where rake can
  # load the Rails environment.
  command "cp config/gitlab.yml.example config/gitlab.yml"
  command "cp config/database.yml.postgresql config/database.yml"
  # There is a bug in the acts-as-taggable-on gem that makes
  # rake assets:precompile check for a database connection. We do not have a
  # database at this point so that is a problem. This bug is fixed in
  # acts-as-taggable-on 3.0.0 by
  # https://github.com/mbleigh/acts-as-taggable-on/commit/ad02dc9bb24ec8e1e79e7e35e2d4bb5910a66d8e
  patch = "#{Omnibus.project_root}/config/patches/acts-as-taggable-on-ad02dc9bb24ec8e1e79e7e35e2d4bb5910a66d8e.diff"
  # To make this idempotent, we apply the patch (in case this is a first run) or
  # we revert and re-apply the patch (if this is a second or later run).
  command "git apply #{patch} || (git apply -R #{patch} && git apply #{patch})",
    :cwd => "#{install_dir}/embedded/service/gem/ruby/1.9.1/gems/acts-as-taggable-on-2.4.1"
  rake "assets:precompile", :env => {"RAILS_ENV" => "production"}
  # Tear down now that the assets:precompile is done.
  command "rm config/gitlab.yml config/database.yml"

  command "mkdir -p #{install_dir}/embedded/service/gitlab-rails"
  command "rm -rf log tmp public/uploads"
  command "#{install_dir}/embedded/bin/rsync -a --delete --exclude=.git/*** --exclude=.gitignore ./ #{install_dir}/embedded/service/gitlab-rails/"

  # Create a wrapper for the rake tasks of the Rails app
  erb :dest => "#{install_dir}/bin/gitlab-rake",
    :source => "bundle_exec_wrapper.erb",
    :mode => 0755,
    :vars => {:command => 'rake "$@"', :install_dir => install_dir}

  # Create a wrapper for the rails command, useful for e.g. `rails console`
  erb :dest => "#{install_dir}/bin/gitlab-rails",
    :source => "bundle_exec_wrapper.erb",
    :mode => 0755,
    :vars => {:command => 'rails "$@"', :install_dir => install_dir}
end