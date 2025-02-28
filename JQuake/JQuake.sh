#!/usr/bin/env bash

cd ~/JQuake

java -jar JQuake.jar -Xmx200m -Xms32m -Xmn2m -Djava.net.preferIPv4Stack=true -Dawt.useSystemAAFontSettings=gasp > /dev/null

