# What is this

This repository includes scripts and documentation to set up the Raspberry Pi that host the services in my home server.

# Initial setup

The Raspberry Pi need some initial manual configuration.

1. Burn Raspbian into the SD card (`rpi-imager` in whatever package manager, remember to select a headless image)
2. Set special settings. We want...
   - A hostname, one of:
     - bastion
     - pihole
     - fileserver
   - A username (dacada) and password (check password manager, different for each device)
   - The right locale and keyboard layout (just in case we need to actually physically log in)
   - Enable ssh with the appropriate public key (check the ansible vault in the fileserver). The format of the input
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

# Trusting keys

I am a lazy man. I don't want to copy over a new key each time I need to let a new device into each of my devices. Instead, we're using a **Certificate Authority**. Within the `secrets.yml` file in the fileserver we have the key pair for the CA. To let a new device into the bastion, simply sign its public key using the CA's private key.

```
ssh-keygen -s ca -I "Some description" -n dacada -V +3550w device.pub
```

This uses `ca`, a private key, to sign `device.pub`, a device's public key. The signature expires after around 70 years. What if a key is compromised?

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

# TODO

In this order:

- Centralize logging to fileserver
- Set up automatic updates
- Set up monitoring
- Set up and expose webserver on bastion with landing page that can reverse proxy to other devices
- Finish setting up the filserver (add deluge)
