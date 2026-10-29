# CCast - A native fast launcher for MacOS
Built with obj-C and C++, without AI things inside (if you want them, just use raycast or something else, idc/k).

## Build
To build the launcher, just run `make` inside of the cloned repo. The project has no dependency.

## Running as an application
To run the executable as an application, you can easily use the “Script Editor” and paste:

``` bash
do shell script "/absolute/path/of/the/exec > /dev/null 2>&1 &"
```

Save the script as *Application* and set “Show Startup screen”.

Also remember to add it to the *startup application* of your system.
