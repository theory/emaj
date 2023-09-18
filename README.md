E-Maj
=====

E-Maj: logs and rollbacks table updates

Version: 4.3.0


License
-------

This software is distributed under the GNU General Public License.


Objectives
----------

The main goals of E-Maj are:

 * log updates performed on one or several sets of tables.
 * cancel these updates if needed, and reset a tables set to a predefined stable state.

In development environments, it brings a good help in testing application, providing an easy way to rollback all updates generated by programs execution, and replay these processings as many times as needed.

In production environments, it brings a good solution to:

 * keep an history of updates performed on tables to examine them in case of problem
 * set inter-batch savepoints on groups of tables,
 * easily "restore" this group of tables at a stable state, without being obliged to stop the cluster,
 * handle several savepoints during batch windows, each of them been usable at any time as "restore point".

It brings a good alternative to the management of several database disk images.

In both environments, being able to examine the history of updates performed on tables can be very helpful in debugging work or for any other purposes.


Distribution
------------

E-Maj is available via the PGXN platform (https://pgxn.org/dist/e-maj/). It is also available on github (https://github.com/dalibo/emaj).


Documentation
-------------

A detailed documentation can be found here, in [English](https://emaj.readthedocs.io/en/latest/) and in [French](https://emaj.readthedocs.io/fr/latest/).


How to install and use E-Maj
----------------------------

E-Maj can be installed using the usual method for postgres extensions (ie. CREATE EXTENSION emaj CASCADE;).

The documentation contains all the [detailled information](https://emaj.readthedocs.io/en/latest/install.html) needed to install and use E-Maj.


Emaj_web GUI
------------

**Emaj_web** is a web GUI tool that brings a user friendly E-Maj administration. It is written in PHP.

The Emaj_web client is available on [github](https://github.com/dalibo/emaj_web).

Its installation and its usage are also described in the [documentation](https://emaj.readthedocs.io/en/latest/webOverview.html).


Contributing
------------

Any contribution on the project is welcome. A part of the documentation deals with [how to contribute](https://emaj.readthedocs.io/en/latest/contributing.html).


Support
-------

For additional support or bug report, please create an issue on the github repository or contact Philippe BEAUDOIN (phb <dot> emaj <at> free <dot> fr).

Any feedback is welcome, even to just notice you use and appreciate E-Maj ;-)
