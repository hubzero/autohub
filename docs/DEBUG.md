# Debugging `autohub` code

`autohub` comes preinstalled with the Xdebug PHP debugging library, which integrates with many popular PHP IDEs.

This makes it easy to set up remote debugging of a hub from your VM host computer.

IDE-specific debug configuration appears below.

## PhpStorm

These instructions assume you have set up the [CLI launcher script](https://www.jetbrains.com/help/phpstorm/working-with-the-ide-features-from-command-line.html). If you haven't, manually open the project and skip the first two steps below.

1. Spin up a hub as per the instructions in the [README](../README.md).
1. From the host machine, go to the webroot:
    `$ cd guestdata/webroot`
1. Launch PhpStorm:
    `$ pstorm .`
1. Click **Run** > **Edit Configurations...** from the menu
1. Click the **+** button and choose **PHP Remote Debug** from the *Add New Configuration* dropdown
1. From the *Pre-configuration* list, click **Validate** from step 1
1. Ensure **Local Web Server or Shared Folder** is selected, then ensure the following are set before clicking the **Validate** button
    - *Path to create validation script*: `<your-dev-dir>/guestdata/webroot/app/templates`
    - *Url to validation script*: `https://devhub.localdomain:5443/app/templates` (change hostname and port if required)
1. You should see something similar to the blow image. Click the **Cancel** button, then click **OK**
1. Open settings (**File** > **Settings** or `Ctrl`+`Alt`+`S`)
1. Select **Languages & Frameworks**, **PHP**
1. Ensure *PHP language level* is set to **5.6**, then under *CLI Interpreter* click the **...** button
1. Click the **+** button, and from the *Select CLI Interpreter* dropdown select **From Docker, Vagrant, VM, WSL, Remote...**
1. Choose the **Vagrant** radio button
1. Click the folder icon button under *Vagrant Instance Folder* and browse to the `autohub` instance folder (the directory you checked out `autohub` into, which contains the `Vagrantfile`), then click the **OK** button
1. *Vagrant Host URL* should auto-populate. Set *PHP interpreter path* to **`/opt/remi/php56/root/usr/bin/php`**, then click the **OK** button, and again on the next screen, and the screen after that
1. Install the **Xdebug helper** browser addon:
    - [Firefox](https://addons.mozilla.org/en-US/firefox/addon/xdebug-helper-for-firefox/)
    - [Chrome](https://chrome.google.com/webstore/detail/xdebug-helper/eadndfjplgieldjbigjakmdgkmoaaaoc)
1. Visit your hub in the same browser (e.g., https://devhub.localdomain:5443)
1. A greyed out "bug" icon should be in your address bar next to the bookmark star (in Firefox). Click it and select **Debug**
1. In the PhpStorm menu, click **Run** > **Start Listening for PHP Debug Connections**
1. Now, set a breakpoint at a location you know will trigger, and reload the webpage
1. You may be prompted to trust a certificate from the hub. Click the **Accept** button
1. Hub code execution should be paused at the breakpoint
