#!/usr/bin/env bash

cd ~/JQuake

java -Xmx200m -Xms32m -Xmn2m -Djava.net.preferIPv4Stack=true -Dawt.useSystemAAFontSettings=gasp -jar JQuake.jar > /dev/null &

