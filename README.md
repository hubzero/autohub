# HUBzero Development VM

## Summary

Sets up a mostly fully functioning HUBzero instance inside a Vagrant VirtualBox-backed VM for CentOS 6.

The goal is to have a setup that fairly closely resembles an actual fully featured production hub that developers can code and test against.

Setting up a hub is tedious work. This helps remove that tedium and allows developers to quickly set up disposable hubs within local development environments.

This is essentially an automation of the [steps documented by HUBzero](https://help.hubzero.org/documentation/22/installation/redhat/install).

Most everything is fully set up, except for things like Submit, which are complex and will require manual intervention to configure properly.


## Usage

**Note**: Only tested on Linux, but should work with macOS and possibly Windows.

Prereqs:

- [VirtualBox](https://www.virtualbox.org/) installed
- [Vagrant](https://www.vagrantup.com/) installed

Check out this repository:

```bash
$ git clone https://gitlab.hubzero.org/hubzero-next/autohub <target-dir>
$ cd <target-dir>
```

Download the base image (this will take some time):

```bash
$ vagrant box add https://help.hubzero.org/app/site/media/vm/metadata.json
```

Review the config in `vars.yml`:

Variable                | Description
--                      | --
`HUBZERO_VAGRANT_BOX`   | Vagrant box name
`VBOX_CPUS`             | Number of VM CPUs
`VBOX_MEMORY`           | VM RAM allocation
`VBOX_HEADLESS`         | Flag to run in headless mode
`HUBNAME`               | HUBzero hub name
`CMS_ADMIN_USER`        | HUBzero admin username (changing this isn't supported currently)
`CMS_ADMIN_PASSWORD`    | HUBzero admin password
`CMS_DB_PASSWORD`       | HUBzero database password
`DB_ROOT_PASSWORD`      | Password for MySQL `root` user
`HOST`                  | Hub subdomain (defaults to `HUBNAME`)
`DOMAIN_NAME`           | Hub primary domain name (combined with `HOST` to get FQDN/hostname)
`HUB_SOURCE_URL`        | HTTP(S) URL of git repo to pull hub source from (if blank, use pre-packaged hub code)
`HUB_SOURCE_BRANCH`     | Branch to checkout when getting source from git repo (default: `master`)
`SOLR_ENABLED`          | Flag to enable Solr search
`HOST_SHARE_DIR`        | Shared directory path on host
`GUEST_SHARE_DIR`       | Shared directory path in guest VM
`HOST_PORT_HTTP`        | Host port to forward guest `80` to
`HOST_PORT_HTTPS`       | Host port to forward guest `443` to
`HOST_PORT_MYSQL`       | Host port to forward guest `3306` to
`HOST_PORT_WSS`         | Host port to forward guest `8443` to
`HOST_PORT_SOLR`        | Host port to forward guest `8445` to
`HOST_PORT_PUBLIC`      | Flag to forward guest ports to `0.0.0.0` instead of default `127.0.0.1`
`HOST_PORT_AUTOCORRECT` | Flag to choose another port to forward to on the host when there is a conflict

`Vagrantfile` controls Vagrant, but most of the interesting options are pulled from `vars.yml`. `provision.sh` does the heavy lifting for setting up the hub. Neither should require modification to get a working hub up unless there are bugs.

Start/provision the VM (this will take a bit of time):

```bash
$ vagrant up
```


## Certificates

While provisining the hub, the script creates a new TLS certificate for HTTPS and the VNC proxy's Secure WebSocket (WSS). You can provide the issuing certificate authority (CA) or not. In the latter case the system will generate its own fake issuing CA first using [minica](https://github.com/jsha/minica).

Providing your own CA can save the tedious work of manually adding a new CA to a browser, because you can install your own CA once, and not have to worry about it for subsequent `autohub` hubs when using the same browser.

The easiest way to do this is to have `autohub` create a fake CA during the initial run, installing that into your browser(s), and saving that CA's cert/key for later use.

After the hub's created, the files `ca.crt` (CA cert) and `ca.key` (CA private key) are placed into the guest's share directory (`./guestdata`). Just copy these out and store somewhere for later use. Then, when spinning up a new hub, just make sure they are in that hub's `./guestdata` directory. The script will use them when creating that hub's cert.

Install the generated `ca.crt` into your browser. Instructions on where this file is located appear after `vagrant up` completes.

First, edit your `/etc/hosts` file and add the line:

```
127.0.0.1    <hubname>.localdomain
```

Firefox:

1. Click the hamburger menu, then **Preferences**
1. Select the **Privacy & Security** tab
1. Click the **View Certificates...** button under *Security* > *Certificates* at the bottom of the page
1. Select the **Authorities** tab
1. Click the **Import...** button
1. Navigate to the directory that holds `<hubname>-devhub-fake-ca.crt`
1. Select the file and click the **Open** button
1. On the *Downloading Certificate* popup, check **Trust this CA to identify websites.**, then click **OK**
1. Click **OK** in *Certificate Manager*

Chrome:

1. Click on the 3 vertical dots, then **Settings**
1. Click **Advanced**, then **Privacy and security**
1. Click on **Manage certificates**
1. Select the **Authorities** tab
1. Click the **Import** button
1. Navigate to the directory that holds `<hubname>-devhub-fake-ca.crt`
1. Select the file and click the **Open** button
1. On the *Certificate authority* popup, check **Trust this certificate for identifying websites**, then click **OK**

Now visit your hub. By default it will have an address like:

https://devhub.localdomain:5443/

Your browser should not complain of an insecure connection. It will complain if you use `localhost` instead though, hence the edit to `/etc/hosts`.


## Make your own custom Vagrant box

Prereqs:

- [VirtualBox](https://www.virtualbox.org/) installed
- [Packer](https://www.packer.io/) installed

The following files in the `packer/` directory control the image build:

File                  | Description
--                    | --
`centos6.json`        | Primary Packer configuration file
`vars.json`           | "Local" variables that override the above
`http/ks.cfg`         | CentOS [Kickstart](https://docs.centos.org/en-US/centos/install-guide/Kickstart2/) config for automated installs
`scripts/vagrant.sh`  | Sets up `vagrant` user SSH
`scripts/vmtools.sh`  | Installs VirtualBox guest additions
`scripts/hubzero.sh`  | Installs HUBzero deps/packages
`scripts/custom.sh`   | Installs custom packages you may want (like `vim`)
`scripts/cleanup.sh`  | Cleans up VM cruft for a smaller image
`scripts/zerodisk.sh` | Writes zeros to the disk's free space for a smaller image

Build the image (this takes a while):

```bash
$ packer build -var-file=vars.json centos6.json
```

To add to Vagrant:

```bash
$ vagrant box add <your-box-name> ~/path-to-box/HUBzero-CentOS-6.10-x86_64-<yyyyMMdd>-virtualbox.box
```

Then in `vars.yml` set `HUBZERO_VAGRANT_BOX: <your-box-name>` and run:

```bash
$ vagrant up
```

To delete the box from Vagrant:

```bash
$ vagrant box remove <your-box-name>
```

See all installed boxes:

```bash
$ vagrant box list
```

To make available remotely via the Internet, `metadata.json` should be updated with the new version, and both it and the `.box` file uploaded to `https://help.hubzero.org` into the `/app/site/media/vm/` directory.

**Note**: The Packer setup here was modified from the [INSANEWORKS CentOS6 template](https://github.com/INSANEWORKS/insaneworks-packer-template).

