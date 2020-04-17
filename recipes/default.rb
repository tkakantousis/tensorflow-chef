private_ip = my_private_ip()

# Only the first tensorflow server needs to create the directories in HDFS
if private_ip.eql? node['tensorflow']['default']['private_ips'][0]

  url=node['tensorflow']['hopstfdemo_url']

  base_filename =  "demo-#{node['tensorflow']['examples_version']}.tar.gz"
  cached_filename = "#{Chef::Config['file_cache_path']}/#{base_filename}"

  remote_file cached_filename do
    source url
    mode 0755
    action :create
  end

  # Extract Jupyter notebooks
  bash 'extract_notebooks' do
    user "root"
    code <<-EOH
                set -e
                cd #{Chef::Config['file_cache_path']}
                rm -rf #{node['tensorflow']['hopstfdemo_dir']}-#{node['tensorflow']['examples_version']}/#{node['tensorflow']['hopstfdemo_dir']}
                mkdir -p #{node['tensorflow']['hopstfdemo_dir']}-#{node['tensorflow']['examples_version']}/#{node['tensorflow']['hopstfdemo_dir']}
                tar -zxf #{base_filename} -C #{Chef::Config['file_cache_path']}/#{node['tensorflow']['hopstfdemo_dir']}-#{node['tensorflow']['examples_version']}/#{node['tensorflow']['hopstfdemo_dir']}
                chown -RL #{node['hops']['hdfs']['user']}:#{node['hops']['group']} #{Chef::Config['file_cache_path']}/#{node['tensorflow']['hopstfdemo_dir']}-#{node['tensorflow']['examples_version']}
        EOH
  end

  hops_hdfs_directory "/user/#{node['hops']['hdfs']['user']}/#{node['tensorflow']['hopstfdemo_dir']}" do
    action :create_as_superuser
    owner node['hops']['hdfs']['user']
    group node['hops']['group']
    mode "1775"
  end

  hops_hdfs_directory "#{Chef::Config['file_cache_path']}/#{node['tensorflow']['hopstfdemo_dir']}-#{node['tensorflow']['examples_version']}/#{node['tensorflow']['hopstfdemo_dir']}" do
    action :replace_as_superuser
    owner node['hops']['hdfs']['user']
    group node['hops']['group']
    mode "1755"
    dest "/user/#{node['hops']['hdfs']['user']}/#{node['tensorflow']['hopstfdemo_dir']}"
  end

  # Feature store tour artifacts
   url=node['featurestore']['hops_featurestore_demo_url']

   base_filename =  "demo-featurestore-#{node['featurestore']['examples_version']}.tar.gz"
   cached_filename = "#{Chef::Config['file_cache_path']}/#{base_filename}"

   remote_file cached_filename do
     source url
     mode 0755
     action :create
   end

  # Extract Feature Store Jupyter notebooks
   bash 'extract_notebooks' do
     user "root"
     code <<-EOH
                set -e
                cd #{Chef::Config['file_cache_path']}
                rm -rf #{node['featurestore']['hops_featurestore_demo_dir']}-#{node['featurestore']['examples_version']}/#{node['featurestore']['hops_featurestore_demo_dir']}
                mkdir -p #{node['featurestore']['hops_featurestore_demo_dir']}-#{node['featurestore']['examples_version']}/#{node['featurestore']['hops_featurestore_demo_dir']}
                tar -zxf #{base_filename} -C #{Chef::Config['file_cache_path']}/#{node['featurestore']['hops_featurestore_demo_dir']}-#{node['featurestore']['examples_version']}/#{node['featurestore']['hops_featurestore_demo_dir']}
                chown -RL #{node['hops']['hdfs']['user']}:#{node['hops']['group']} #{Chef::Config['file_cache_path']}/#{node['featurestore']['hops_featurestore_demo_dir']}-#{node['featurestore']['examples_version']}
     EOH
   end

   hops_hdfs_directory "/user/#{node['hops']['hdfs']['user']}/#{node['featurestore']['hops_featurestore_demo_dir']}" do
     action :create_as_superuser
     owner node['hops']['hdfs']['user']
     group node['hops']['group']
     mode "1775"
   end

   hops_hdfs_directory "#{Chef::Config['file_cache_path']}/#{node['featurestore']['hops_featurestore_demo_dir']}-#{node['featurestore']['examples_version']}/#{node['featurestore']['hops_featurestore_demo_dir']}" do
     action :replace_as_superuser
     owner node['hops']['hdfs']['user']
     group node['hops']['group']
     mode "1755"
     dest "/user/#{node['hops']['hdfs']['user']}/#{node['featurestore']['hops_featurestore_demo_dir']}"
   end

end

# Install nvm to manage different Node.js versions
bash "install nvm" do
  user "root"
  group "root"
  environment ({ 'NVM_DIR' => '/usr/local/nvm'})
  code <<-EOF
       mkdir -p /usr/local/nvm
       curl -o- https://raw.githubusercontent.com/creationix/nvm/v0.33.8/install.sh | bash
       chgrp -R #{node['hops']['group']} /usr/local/nvm
       chmod -R g+w /usr/local/nvm
  EOF
  not_if { ::File.exists?("/usr/local/nvm/nvm.sh") }
end

bash "install Node.js v10.16.0" do
  user node['conda']['user']
  group node['hops']['group']
  cwd "/home/#{node['conda']['user']}"
  environment ({ 'NVM_DIR' => '/usr/local/nvm'})
  code <<-EOF
       source /usr/local/nvm/nvm.sh
       nvm install 10.16.0
  EOF
end

# Download Hopsworks jupyterlab_git plugin
if node['install']['enterprise']['install'].casecmp? "true"
  cached_file = "jupyterlab_git-#{node['conda']['jupyter']['jupyterlab-git']['version']}-py3-none-any.whl"
  source = "#{node['install']['enterprise']['download_url']}/jupyterlab_git/#{node['conda']['jupyter']['jupyterlab-git']['version']}/#{cached_file}"
  remote_file "#{::Dir.home(node['conda']['user'])}/#{cached_file}" do
    user node['conda']['user']
    group node['conda']['group']
    source source
    headers get_ee_basic_auth_header()
    sensitive true
    mode 0555
    action :create_if_missing
  end
end

bash 'extract_sparkmagic' do
  user "root"
  group "root"
  cwd Chef::Config['file_cache_path']
  umask "022"
  code <<-EOF
    set -e
    rm -rf sparkmagic 
    rm -rf #{node['conda']['dir']}/sparkmagic
    tar zxf sparkmagic-#{node['jupyter']['sparkmagic']['version']}.tar.gz
    mv sparkmagic #{node['conda']['dir']}
  EOF
end

# make sure Kerberos dev are installed
case node['platform_family']
when "debian"
  package ["libkrb5-dev", "libsasl2-dev"]
when "rhel"
  package ["krb5-devel", "krb5-workstation", "cyrus-sasl-devel"]
end

python_versions = node['kagent']['python_conda_versions'].split(',').map(&:strip)

for python in python_versions

  envName = "python" + python.gsub(".", "")

  bash "remove_base_env-#{envName}" do
    user 'root'
    group 'root'
    umask "022"
    cwd "/home/#{node['conda']['user']}"
    code <<-EOF
      set -e
      #{node['conda']['base_dir']}/bin/conda env remove -y -q -n #{envName}
    EOF
    only_if "test -d #{node['conda']['base_dir']}/envs/#{envName}", :user => node['conda']['user']
  end

  Chef::Log.info "Environment creation for: python#{python}"



  bash "create_base_env-#{envName}" do
    user node['conda']['user']
    group node['conda']['group']
    umask "022"
    environment ({ 'HOME' => ::Dir.home(node['conda']['user']), 'USER' => node['conda']['user'] })
    code <<-EOF
    set -e
    cd $HOME
    export CONDA_DIR=#{node['conda']['base_dir']}
    export PY=`echo #{python} | sed -e "s/\.//"`
    export ENV=#{envName}

    ${CONDA_DIR}/bin/conda create -n $ENV python=#{python} -y -q

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade requests

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade ipykernel hops-ipython-sql
    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade matplotlib
    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install nvidia-ml-py3==#{node['conda']['nvidia-ml-py']['version']}
    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install avro-python3==#{node['avro-python3']['version']}

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --no-cache-dir --upgrade witwidget
    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip uninstall tensorflow
    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip uninstall tensorboard
    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip uninstall tensorflow-estimator
    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip uninstall tensorflow-serving-api

    export ROCM=#{node['rocm']['install']}
    export CUSTOM_TF_URL=#{node['tensorflow']['custom_url']}
    # Install a custom build of tensorflow with this line.
    if [ ! -z $CUSTOM_TF_URL ] ; then
      yes | #{node['conda']['base_dir']}/envs/${ENV}/bin/pip install $CUSTOM_TF_URL --upgrade --force-reinstall
    elif [ -f /opt/rocm/bin/rocminfo ] || [ $ROCM == "true" ]  ; then
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install tensorflow-rocm==#{node['tensorflow']['rocm']['version']}
    else
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install tensorflow==#{node['tensorflow']["version"]} --upgrade --force-reinstall
    fi

    export HOPS_UTIL_PY_VERSION=#{node['conda']['hops-util-py']['version']}
    export HOPS_UTIL_PY_BRANCH=#{node['conda']['hops-util-py']['branch']}
    export HOPS_UTIL_PY_REPO=#{node['conda']['hops-util-py']['repo']}
    export HOPS_UTIL_PY_INSTALL_MODE=#{node['conda']['hops-util-py']['install-mode']}
    if [ $HOPS_UTIL_PY_INSTALL_MODE == "git" ] ; then
        yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install git+https://github.com/${HOPS_UTIL_PY_REPO}/hops-util-py@$HOPS_UTIL_PY_BRANCH
    else
        yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install hops==$HOPS_UTIL_PY_VERSION
    fi

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade pyjks

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade confluent-kafka

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade hops-petastorm

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade opencv-python

    if [[ "#{node['maggy']['version']}" =~ ^git.* ]] ; then
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install #{node['maggy']['version']}
    else
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install maggy==#{node['maggy']['version']}
    fi

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade tqdm

    export PYTORCH_CHANNEL=#{node['conda']['channels']['pytorch']}
    if [ "${PYTORCH_CHANNEL}" == "" ] ; then
      PYTORCH_CHANNEL="pytorch"
    fi

    if [ -f /usr/local/cuda/version.txt ]  ; then
      nvidia-smi -L | grep -i gpu
      if [ $? -eq 0 ] ; then
        ${CONDA_DIR}/bin/conda install -y -n ${ENV} -c ${PYTORCH_CHANNEL} pytorch=#{node['pytorch']['version']}=#{node["pytorch"]["python3"]["build"]} torchvision=#{node['torchvision']['version']}
      else
        ${CONDA_DIR}/bin/conda install -y -n ${ENV} -c ${PYTORCH_CHANNEL} pytorch==#{node['pytorch']['version']} torchvision==#{node['torchvision']['version']} cpuonly
      fi
    else
      ${CONDA_DIR}/bin/conda install -y -n ${ENV} -c ${PYTORCH_CHANNEL} pytorch==#{node['pytorch']['version']} torchvision==#{node['torchvision']['version']} cpuonly
    fi

    # for sklearn serving
    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade Flask

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade scikit-learn

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade seaborn

    yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade pyopenssl

    EOF
  end

  bash "pydoop_base_env-#{envName}" do
    user "root"
    umask "022"
    code <<-EOF
    set -e
    export CONDA_DIR=#{node['conda']['base_dir']}
    export ENV=#{envName}
    su #{node['conda']['user']} -c "export HADOOP_HOME=#{node['install']['dir']}/hadoop; export PATH=${PATH}:#{node['install']['dir']}/hadoop/bin; yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install pydoop==#{node['conda']['pydoop']['version']}"
    EOF
  end

  bash "jupyter_sparkmagic_base_env-#{envName}" do
    user node['conda']['user']
    group node['conda']['group']
    umask "022"
    retries 1
    cwd "#{node['conda']['dir']}/sparkmagic"
    environment ({ 'HOME' => ::Dir.home(node['conda']['user']),
                  'USER' => node['conda']['user'],
                  'JAVA_HOME' => node['java']['java_home'],
                  'CONDA_DIR' => node['conda']['base_dir'],
                  'HADOOP_HOME' => node['hops']['base_dir'],
                  'ENV' => envName})
    code <<-EOF
      set -e
      # Install packages and pin working versions
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --no-cache-dir --upgrade jupyterlab==#{node['conda']['jupyter']['version']['py3']}
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --no-cache-dir --upgrade notebook==#{node['conda']['jupyter']['notebook']['version']}
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --no-cache-dir --upgrade tornado==#{node['conda']['jupyter']['tornado']['version']}
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --no-cache-dir --upgrade prompt-toolkit==#{node['conda']['jupyter']['prompt-toolkit']['version']}

      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --upgrade ./hdijupyterutils ./autovizwidget ./sparkmagic

      ${CONDA_DIR}/envs/${ENV}/bin/jupyter nbextension enable --py --sys-prefix widgetsnbextension

      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --no-cache-dir --upgrade hdfscontents urllib3 requests pandas

      # Install wit-widget JupyterLab extension
      source /usr/local/nvm/nvm.sh
      nvm use 10.16.0
      ${CONDA_DIR}/envs/${ENV}/bin/jupyter labextension install --no-build wit-widget
      ${CONDA_DIR}/envs/${ENV}/bin/jupyter labextension install --no-build @jupyter-widgets/jupyterlab-manager
      # Enable nbdime
      ${CONDA_DIR}/envs/${ENV}/bin/jupyter labextension install --no-build nbdime-jupyterlab
      ${CONDA_DIR}/envs/${ENV}/bin/jupyter lab build

      # Enable kernels
      cd ${CONDA_DIR}/envs/${ENV}/lib/python#{python}/site-packages

      ${CONDA_DIR}/envs/${ENV}/bin/jupyter-kernelspec install sparkmagic/kernels/sparkkernel --sys-prefix
      ${CONDA_DIR}/envs/${ENV}/bin/jupyter-kernelspec install sparkmagic/kernels/pysparkkernel --sys-prefix
      ${CONDA_DIR}/envs/${ENV}/bin/jupyter-kernelspec install sparkmagic/kernels/sparkrkernel --sys-prefix
      
    EOF
  end

  # Install Hopsworks jupyterlab-git plugin
  if node['install']['enterprise']['install'].casecmp? "true"
    # Fourth digit of the version is Hopsworks versioning
    upstream_extension_version = node['conda']['jupyter']['jupyterlab-git']['version'].split(".")[0...3].join(".")
    bash "install jupyterlab-git python#{python}" do
      user node['conda']['user']
      group node['conda']['user']
      environment ({ 'HOME' => ::Dir.home(node['conda']['user']),
                     'USER' => node['conda']['user'],
                     'CONDA_DIR' => node['conda']['base_dir'],
                     'ENV' => envName,
                     'GIT_PYTHON_REFRESH' => 's'})
      code <<-EOF
      source /usr/local/nvm/nvm.sh
      nvm use 10.16.0      
      ${CONDA_DIR}/envs/${ENV}/bin/jupyter labextension install @jupyterlab/git@#{upstream_extension_version}
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --no-cache-dir --upgrade #{::Dir.home(node['conda']['user'])}/jupyterlab_git-#{node['conda']['jupyter']['jupyterlab-git']['version']}-py3-none-any.whl
      ${CONDA_DIR}/envs/${ENV}/bin/jupyter serverextension enable --sys-prefix --py jupyterlab_git
    EOF
   end
  end

  if node['conda']['additional_libs'].empty? == false
    add_libs = node['conda']['additional_libs'].split(',').map(&:strip)
    for lib in add_libs
      bash "libs_py#{python}_env" do
        user node['conda']['user']
        group node['conda']['group']
        umask "022"
        environment ({ 'HOME' => ::Dir.home(node['conda']['user']),
                  'USER' => node['conda']['user'],
                  'JAVA_HOME' => node['java']['java_home'],
                  'CONDA_DIR' => node['conda']['base_dir'],
                  'HADOOP_HOME' => node['hops']['base_dir'],
                  'ENV' => envName
                  })
        code <<-EOF
      cd $HOME
      yes | ${CONDA_DIR}/envs/${ENV}/bin/pip install --no-cache-dir --upgrade #{lib}
    EOF
      end
    end
  end
end

#
# Need to synchronize conda environments for newly joined or rejoining nodes.
#
package "rsync"

#
# Allow hopsworks/user to ssh into servers with the anaconda user to make a copy of environments.
#
homedir = node['conda']['user'].eql?("root") ? "/root" : "/home/#{node['conda']['user']}"
kagent_keys "#{homedir}" do
  cb_user "#{node['conda']['user']}"
  cb_group "#{node['conda']['group']}"
  cb_name "hopsworks"
  cb_recipe "default"
  action :get_publickey
end
