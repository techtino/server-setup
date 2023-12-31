# Server Setup script

This is my server setup script I use for setting up:
1. Install dependencies.
2. Mounting my NAS locally via systemd mount.
3. Create a systemd service to run my containers via docker-compose
4. If the container data isn't already copied over, then rsync them from the latest snapshot on my NAS.
5. Setup a backup script that backs up my container data to my NAS daily,  It utilises hardlinks so you don't do a fresh rsync if the data matches.
6. Setup a systemd timer that will run the backup daily at 10am. (This is almost definitely overkill).

This is mostly use for my home server.

Notes for future self:
Debian by default doesn't setup systemd-networkd or networkmanager if you install it without a gui. This is obviously fine, except for the fact that network-online.target relies on either systemd-networkd (systemd-networkd-wait-online.service) or networkmanager (NetworkManager-wait-online.service). In this case I set up systemd-networkd as per https://wiki.debian.org/SystemdNetworkd and then enabled systemd-networkd-wait-online, so it's now working.
