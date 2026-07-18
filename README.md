# What is this

This repository includes scripts and documentation to set up the Raspberry Pi that host the services in my home server.

# Initial setup

## Raspberry Pi

The Raspberry Pi need some initial manual configuration.

1. Burn Raspbian into the SD card (`rpi-imager` in whatever package manager, run it under `sudo -E`, remember to select a headless image)
2. Set special settings. We want...
   - A hostname, one of:
     - bastion
     - pihole
     - fileserver
   - A username (dacada) and password (check password manager, different for each device)
   - The right locale and keyboard layout (just in case we need to actually physically log in)
   - Enable ssh with the automation public key (check the ansible vault in the fileserver). The format of the input
     should be: `from="192.168.1.0/24" THE KEY HERE`. That option at the start may make it just slightly more secure?
   - Disable telemetry
3. Configure in a static IP address. Mount /dev/sdX1 and edit cmdline.txt to put the following at the end:
```
ip=192.168.1.XXX::192.168.1.1:255.255.255.0::eth0:off
```
   Make sure to choose the right static IP
+------------+---------------+
| hostname   | ip            |
+------------+---------------+
| bastion    | 192.168.1.41  |
| pihole     | 192.168.1.72  |
| fileserver | 192.168.1.103 |
+------------+---------------+
4. Ensure the ansible vault is in the correct path. Copy it over from the fileserver if needed (copy it to `ansible/vars/secrets.yml`). If it has been lost, you will need to create a new one! Check the section about creating a new ansible vault.
5. Run Ansible: `ansible-playbook -i ansible/inventories/hosts ansible/playbooks/site.yml --ask-vault-pass` (the password is, of course, in your password manager)

## Offsite server

Set the server into a baseline Debian server (latest Stable). Reset the root password. Log in via console (ssh won't allow root password login). Ensure we allow ssh ingress via IPv4 at least. And allow ingress via whichever port the backup solution wants to use (TBD).

Set up the server, as root:
```bash
# setup dacada user with password from password manager and sudo access
adduser dacada
usermod -aG sudo dacada
echo "dacada ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/010_pi-nopasswd

# install the automation public ssh key
install -d -m 700 -o dacada -g dacada /home/dacada/.ssh
cat >> /home/dacada/.ssh/authorized_keys  # enter the public key here
chown dacada:dacada /home/dacada/.ssh/authorized_keys
chmod 600 /home/dacada/.ssh/authorized_keys

# set hostname
hostnamectl hostname offsite
vim /etc/hosts  # optional: to avoid complaints about offsite being an unknown host

# harden ssh
vim /etc/ssh/sshd_config
systemctl reload ssh
```

SSH hardening options:

```config
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
UsePAM yes
```

Verify ssh and sudo access with the automation key. Remember to set the static IP of the server to the correct DNS record. That DNS record is used throughout here (it is actually in the secret vars for extra safety).


# Trusting keys

I am a lazy man. I don't want to copy over a new key each time I need to let a new device into each of my devices. Instead, we're using a **Certificate Authority**. Within the `secrets.yml` file in the fileserver we have the key pair for the CA. To let a new device into the bastion, simply sign its public key using the CA's private key.

```
ssh-keygen -s ca -I "Some description" -n dacada -V +3550w device.pub
```

This uses `ca`, a private key, to sign `device.pub`, a device's public key. The signature expires after around 70 years.

When signing a key, use the `-n` flag to specify the principal(s) for that certificate. The principal must match the username on the target system. For example:

- To sign a key for the `dacada` user: `ssh-keygen -s ca -I "My Laptop" -n dacada -V +3550w laptop.pub`

The principal is enforced on each host—a certificate signed with `-n dacada` can only authenticate as the `dacada` user, and cannot be used to log in as any other user, even if the signed certificate is presented.

What if a key is compromised?

1. We replace the CA in `secrets.yml` with a new one (generated like any other key pair, `ssh-keygen -t rsa -b 4096 -f ca`)
2. We run ansible to make the replacement effective.
3. We go and re-sign every other key.

This is a huge pain. But the way I use keys, they are unlikely to be compromised. This also means I need to be sure to replace keys if they become cryptographically insecure. Which is also something that shouldn't happen often.

In this same repository there is a sample ssh configuration for connecting to the devices from both the LAN and the internet (WAN).

# Manually formatting the SSD

I didn't want to have Ansible automatically reformat the SSD if it can't detect it. Sounds a bit too dangerous. Instead, if it can't find the expected mountpoints it will fail loudly. And point you to the README. Here!

These are the steps to manually set up a new SSD:

1. Ensure the SSD is connected
   ```
   $ lsblk
   ```
   The output should be something like
   ```
   NAME        MAJ:MIN RM   SIZE RO TYPE MOUNTPOINTS
   mmcblk0     179:0    0  59.5G  0 disk
   ├─mmcblk0p1 179:1    0   512M  0 part /boot/firmware
   └─mmcblk0p2 179:2    0    59G  0 part /
   nvme0n1     259:0    0 931.5G  0 disk
   ```
2. Partition the SSD. We want a 25 GB partition for logs (honestly, way too much). And the rest for files.
   ```
   # fdisk /dev/nvme0n1
   ```
   We want the partition table to look something like this:
   ```
   Device            Start        End    Sectors   Size Type
   /dev/nvme0n1p1     2048   20973567   20971520    10G Linux filesystem
   /dev/nvme0n1p2 20973568 1953523711 1932550144 921.5G Linux filesystem
   ```
3. Format the filesystems
   ```
   # mkfs.ext4 /dev/nvme0n1p1
   # mkfs.ext4 /dev/nvme0n1p2
   ```
4. Create mountpoints (if they don't already exist) and mount the partitions. Make sure everything works smoothly.
   ```
   # mkdir -p /mnt/logs
   # mkdir -p /mnt/files
   # mount /dev/nvme0n1p1 /mnt/logs
   # mount /dev/nvme0n1p2 /mnt/files
   # ls /mnt/logs
   # ls /mnt/files
   ```
5. Get the UUIDs of the partitions (may need to run as root to see the new partitions)
   ```
   # blkid
   ```
6. Add partitions to `fstab`
   ```
    # echo "UUID=[UUID OF THE LOGS PARTITION] /mnt/logs ext4 defaults 0 2" >> /etc/fstab
    # echo "UUID=[UUID OF THE FILES PARTITION] /mnt/files ext4 defaults 0 2" >> /etc/fstab
   ```

# Creating a new Ansible Vault

Oopsie, we deleted the vault. To create a new one, first create the actual file: `ansible-vault create secrets.yml`. Then edit it `ansible-vault edit secrets.yml`. The password should be the one in your password manager.

It should contain the following, organized like this:

```yaml
ssh_keys:
  automation:
    private_key: |
      KEY HERE
    public_key: |
      KEY HERE
  bastion:
    private_key: |
      KEY HERE
    public_key: |
      KEY HERE
  ca:
    private_key: |
      KEY HERE
    public_key: |
      KEY HERE
  pihole:
    private_key: |
      KEY HERE
    public_key: |
      KEY HERE
  fileserver:
    private_key: |
      KEY HERE
    public_key: |
      KEY HERE
```

And then we just generate all these keys!

You'll have to go and install the public automation key to every device (see above, in setup, for the format) and then run ansible to set up everything else. After that you'll have to re-sign the key on every device using the CA (see above, in Trusting Keys).

# Setting up VPN clients

Clients must have a private/public key pair, be added to the server so it knows to trust them, and be configured to talk to the server.

In the server config, a `[Peer]` entry has to exist with the client's public key and the IP it will have in the VPN network. There are already several of these here.

In the client, they must have a specific config. Here's an example where...

- `abc123` is the client's private key
- `def456` is the server's public key
- `10.69.42.0/24` is the subnet for the VPN (the current subnet in the playbooks)
- Within that subnet, the client will be on `.99`
- The server endpoint is example.com and it uses the port 99999

```
[Interface]
PrivateKey = abc123
Address = 10.69.42.99/32
DNS = 10.69.42.2  # Optional, if we want to use the pihole as DNS

[Peer]
PublicKey = def456
Endpoint = example.com:99999
AllowedIPs = 192.168.1.0/24, 10.69.42.0/24
```

# Pihole

Pihole is installed manually, using the instructions on the official website. Additionally, it must be configured (through the Web UI) to serve requests from any network. This is vital to get it working from the VPN, and safe as long as I never expose the service out on the Internet.

# Permissions

The permissions for the fileserver should be every file under the smb user and group, 770 permissions. And for the seedbox, within the directory, everything owned by the deluge running user and group, 775 so others (smb) can read. I couldn't find a good succint way to express this in ansible for existing files, but new files should work like this with the way ansible sets up things.

# Deluge

TCP and UDP ports NATed to the fileserver, check Deluge config for the exact ones.

# SSH/VPN NAT

* WAN port 42420 for the ssh into the LAN port 22 of the bastion
* WAN and LAN port 51820 for the VPN into the bastion

# Syncthing Setup

## Initial Access

Access the Syncthing UI through an SSH tunnel:

```bash
ssh -L 8384:localhost:8384 fileserver
```

Then open:

```
http://localhost:8384
```

## UI Configuration

Configure the GUI username as `sync`, set the GUI password, disable "Start Browser", and change the GUI listen address to `0.0.0.0:8384`. Verify that the UI is reachable at `http://<fileserver-ip>:8384`, then the SSH tunnel is no longer required.

## Folder Setup

Delete the default folder.

## Device Setup

For each existing device (desktop, laptop, phone), add the `fileserver` device and accept the request on the fileserver UI. Share the existing Syncthing folder with `fileserver` and accept the folder on the fileserver UI, using `/mnt/files/syncthing` as the folder path.

The final state should be a single shared folder with all devices participating:

* desktop
* laptop
* phone
* fileserver

# TODO

In this order:

- Set up and expose webserver on bastion with landing page that can reverse proxy to other devices (Homepage?)
- Biwarden/vaultwarden?
