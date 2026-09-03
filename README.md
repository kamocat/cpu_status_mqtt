# cpu_status_mqtt
Send CPU/memory/hard drive status info over MQTT for HomeAssistant

## Requirements
- mosquitto_client
- sysstat
- perl
- systemd

## Getting started
- Create a mqtt.env with your server config
- Create the discovery message with `perl generate_discovery.pl`
- Test sending the data with `perl cmd.pl`
- Update `cpu_status.service` with the actual location of `cmd.pl` and your username
- Copy the .service and .timer files to `/etc/systemd/system/`
- Enable and start the timer with `systemctl enable cpu_status.timer && systemctl start cpu_status.timer`

## Hacking
- To change the update rate, modify `cpu_status.timer`. Make sure the mqtt_expiry in `generate_discovery.pl` is a bit longer than the update period.