mung.pl
====

An XML-based hierarchical text replacement tool written in Perl by Erik Gillespie.

    USAGE : mung.pl [-r] -e environment [ -f config_file ] file1 directory1 file2 . . .

    For the command line parsing.  Here's the parameter info:
     -e environment          Name of environment to configure.  Must exist in configuration file.
                             Required.  No default value.
     -f config_filename      Path to an alternate XML file to use for configuration information.
                             Optional.  Default value = "mung.xml".
     -r                      Enable recursive search through any directories passed.

## History

mung.pl was created as a way for me to keep track of all of the configuration for various
projects that I worked on at home.  Usually I needed a basic set of default values and
beyond that I needed a way to have configuration that could be overridden for specific
servers or development boxes (my software might be configured in Mac OS X differently
than I would need it configured in Windows).  Not only that, but I might have more than
one server of the same OS that I would want to deploy my software to and certain points
of configuration between those environments might be different (IP address for example).

So mung.pl is the solution I came up with.  It's a perl script that takes an environment
name as a parameter, builds up the configuration for that environment using an XML file
that contains all of the configuration values, and then replaces all property names in
the list of files and directories supplied with the appropriate value.

The program is basically a complicated recursive search and replace.  You started out by
created a mung.xml file where you will place your properties and values.  Then you create
a set of global variables that are effectively the default values for your whole
configuration.  Finally, you provide a set of environment definitions that override the
global configuration by supplying other values.  These environment definitions can also
inherit properties from other environments, which can really simplify the configuration
when you are setting up a lot of similar servers.

## Technical Notes

1. This program was written in Perl to be cross-platform.
2. The left and right delimiters can be customized.
3. The files being configured are read line by line and substitutions are written to a
   file of the same base name with an additional extension of ".mung" first, and then
   the file is moved over top of the original.  A command line argument should probably
   be provided that allows the ".mung" files to be written while leaving the original
   files intact.
4. The mung.xml is first validated against mung.dtd before any parsing is attempted.
5. A list of files and directories to be configured can be provided on the command line
   to be configured.  Directories can optionally be recursed into to easily configure a
   whole project structure.

## Example

The following mung.xml file is a basic example of how you can use this tool.

    <?xml version="1.0"?>
    <!DOCTYPE config SYSTEM "mung.dtd">
    <config ldelim="[" rdelim="]">
     <global name="project.name" value="My Webserver" />
     <global name="hostname" value="localhost" />
     <global name="port.base" value="2" />
     <global name="port" value="[port.base]000" />
     <global name="db.server" value="[hostname]:[port]" />

     <!-- D1 -->
     <env name="d1">
      <var name="port" value="5000" />
     </env>

     <env name="dev1server1" inherit="d1">
      <var name="hostname" value="dev1serv1" />
      <var name="port" value="5001" />
     </env>

     <env name="dev1server2" inherit="d1">
       <var name="hostname" value="dev1server2" />
     </env>

     <!-- D2 -->
     <env name="d2">
      <var name="port.base" value="5" />
     </env>

     <env name="dev2server1" inherit="d2">
      <var name="hostname" value="dev2server1" />
      <var name="port" value="5002" />
     </env>

     <env name="dev2server2" inherit="d2">
      <var name="hostname" value="dev2server1" />
     </env>

    </config>
