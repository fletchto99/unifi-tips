# Unifi Tips

This repo contains a bunch of tip/tricks I use in my Unifi setup. I should note that I'm running the USG Pro. Sorry for how unformal it is, this is mostly just a guide for me so I remember what I change :)

## Custom Software

Below is a list of custom software I run on my USG

1. Nano (because I can never remember Vi bindings :joy:)
2. DDNS (custom setup w/ cloudflare)
3. DNScrypt (for DoH)
4. Wireguard

# Using a Custom Config

To make use of a custom [`config.gateway.json`](https://help.ubnt.com/hc/en-us/articles/215458888-UniFi-USG-Advanced-Configuration#3) file you'll need to connect to your controller. In my case I'm using the [`unifi-controller`](https://hub.docker.com/r/linuxserver/unifi-controller) docker container in Unraid. For the case of this continer the config will exist at `<appdata_path>/data/sites/<site_name>/config.gateway.json`. Whenever this file is modified you can force the USG to re-provision with the new settings via the controller. Before re-provisioning use a [JSON validator](https://jsonformatter.curiousconcept.com/) to ensure you are passing valid JSON. The USG really doesn't like being re-provisioned with an invalid configuration and this may soft-brick your router requiring a factory reset.

Some of the steps below will require the ability to install packages. To do so you'll need to add the following to your `config.gateway.json`:

```
{
  "system":{
    "package":{
      "repository":{
        "wheezy":{
          "components":"main contrib non-free",
          "distribution":"wheezy",
          "url":"http://archive.debian.org/debian"
        }
      }
    }
  }
}
```

Once this is done, force re-provisioning and then SSH into your USG. Lastly run `sudo apt-get update` to fetch the package lists.

**Note:** Never do a bulk upgrade (e.g. `apt-get upgrade`) as this can soft-brick the router requiring a factory reset to fix it.

# Installing Custom Software

## Nano

Assuming you've followed the steps above to setup the package repository all you need to do is SSH into your USG and run `sudo apt-get install nano`.

## DDNS

I've got servers running from within my network as well as a VPN so I use DDNS to update my cloudflare DNS records auto-magically. Unfortunately the built-in DDNS client doesn't support cloudflare's new API - so we need to manually update the `ddclient` version. I was able to follow the instructions on [ubnt wiki](https://ubntwiki.com/notebook/cloudflare_ddns_configuration) to set this up.

- SSH into your router and switch to root via `sudo -i`
- DDClient depends on a library, to install it you'll need to do: `apt-get install libdata-validate-ip-perl `
- Next install the latest [ddclient](https://github.com/ddclient/ddclient) (3.9.1 at the time of writing): `curl -sL https://raw.githubusercontent.com/ddclient/ddclient/master/ddclient -o /usr/sbin/ddclient`

Now you'll need to setup your USG configuration file:

```
{
  "service":{
    "dns":{
      "dynamic":{
        "interface":{
          "<WAN_INTERFACE>":{
            "service":{
              "cloudflare":{
                "host-name":[
                  "<HOSTNAME_TO_UPDATE>"
                ],
                "login":"<CLOUDFLARE_LOGIN>",
                "options":[
                  "zone=<CLOUDFLARE_DOMAIN>"
                ],
                "password":"<CLOUDFLARE_PAT>",
                "protocol":"cloudflare"
              }
            }
          }
        }
      }
    }
  }
}
```

Be sure to update all of the configuration variables here. To get your `WAN_INTERFACE` you can use the command `show interfaces` on the USG and the interface with your public IP is the one you want to put here. Lastly re-provision your USG with the new config.

To test you can use `update dns dynamic interface <WAN_INTERFACE>` and to validate that the DDNS worked successfully you can use `show dns dynamic status`

## DNSCrypt

I've got an interesting DNS setup at home. Essentially I route all traffic through my USG which routes it through PiHole running on a separate server and then back to the USG for DNScrypt. I've got dnscrypt-proxy being used to route DNS via DNS over HTTPS to various resolvers, with the primary being cloudflare.


### Installation:

Installation is pretty straightforward. Essentially to need to download the binary and setup the configs. Here are some step by step instructions:

- SSH into your USG and switch to root using `sudo -i`
- Make the dnscrypt directory `mkdir /otp/dnscrypt`
- Set perms `chmod 777 /opt/dnscrypt/`
- navigate to that dir `cd /opt/dnscrypt`
- Download the latest `dnscrypt-proxy-mips64` binray from [dnscrypt/dnscrypt-proxy](https://github.com/dnscrypt/dnscrypt-proxy/releases) using `curl -sL https://github.com/DNSCrypt/dnscrypt-proxy/releases/download/2.0.39/dnscrypt-proxy-linux_mips64-2.0.39.tar.gz -o dnscrypt.tar.gz`
- unpack the binary `tar -xvzf dnscrypt.tar.gz linux-mips64/dnscrypt-proxy`
- move the binary to the current dir `mv linux-mips64/* .`
- cleanup `rm dnscrypt.tar.gz && rm -r linux-mips64`
- make the dnscrypt binary executable `chmod +x dnscrypt-proxy`
- set ownership `chown root:root dnscrypt-proxy`
- Upload the config from this repo `dnscrypt/dnscrypt-proxy.toml`
  - This will have DNSCrypt running on port `5053` - the USG runs dnsmasq on 53 so you can't run there
  - I use the following resolvers: ['cloudflare', 'quad9-dnscrypt-ip4-filter-pri', 'dnscrypt.ca-1-doh']
  - I use the following fallback resolvers: ['1.1.1.1:53', '8.8.8.8:53', '9.9.9.9:53']
- Lastly, setup dnscrypt as a service `./dnscrypt-proxy -service install`
  - This will set dnscrypt as a service which will work across reboots
  - If you change the config use `sudo service dnscrypt-proxy restart`

### Force traffic to use DNScrypt

I like to have all of my DNS traffic routed through DNScrypt and my PiHole which is running on another server. It even works for those pesky IoT devices which are hardcoded for their own DNS servers. Essentially DNS traffic in my setup looks like this:

Device -> USG (nat rule) -> PiHole -> USG (port 53) -> dnscrypt (port 5053)

To setup the NAT rule as well as the DNSMasq options you can add the following to your `config.gateway.json`. Note in the forwarding options I set `strict-order` followed by specifying the servers below. The ordering of the servers is actually reversed! It will attempt to use the from the bottom up.

```
{
  "service":{
      "forwarding":{
        "options":[
          "host-record=unifi,10.10.10.1",
          "ptr-record=1.10.10.10.in-addr.arpa,Guardian",
          "no-resolv",
          "strict-order",
          "stop-dns-rebind",
          "bogus-priv",
          "expand-hosts",
          "domain-needed",
          "server=1.0.0.1",
          "server=1.1.1.1",
          "server=<USG_IP>#5053",
          "server=<PIHOLE_IP>#<PIHOLE_PORT>"
        ]
      }
    },
    "nat":{
      "rule":{
        "1":{
          "description":"Redirect DNS queries LAN",
          "destination":{
            "port":"53"
          },
          "source":{
            "address":"!<USG_IP>"
          },
          "inside-address":{
            "address":"<LAN_NETWORK>"
          },
          "inbound-interface":"eth0",
          "protocol":"tcp_udp",
          "type":"destination"
        }
      }
    }
  }
}
```

Lastly, all that's required is that you force re-provision your USG. To test you can use [DNSleaktest](https://www.dnsleaktest.com/) to ensure you're using the servers you specified. If that's the case your DNS traffic will be encrypted and only these servers can see your requests. This is even the case for devices with hardcoded DNS (e.g. Alexa echo devices).

## Wireguard

Credits to [this tutorial](https://graham.hayes.ie/posts/wireguard-%2B-unifi/) for helping me get it set up in the first place.

- SSH into your USG and switch to the root account via `sudo -i`
- Install the correct wireguard package from [wireguards/vyatta-wireguard](https://github.com/WireGuard/wireguard-vyatta-ubnt/releases)
  - `curl -sL https://github.com/WireGuard/wireguard-vyatta-ubnt/releases/download/<version>/wireguard-<board>-<version>.deb -o wg.deb`
- `dpkg -i wg.deb` to install wireguard

Next we'll setup the auth configuration:

- Make the configs directory `mkdir /config/auth/wireguard`
- Setup permissions on the directory `chmod 777 /config/auth/wireguard`
- Generate the wireguard server keys `wg genkey | tee wg_private.key | wg pubkey > wg_public.key`
- Generate the client keys `wg genkey | tee client1_private.key | wg pubkey > client1_public.key`
  - You'll need to do this for each client you have
- Now you need to update your `config.gateway.json` with the following information:

```
{
  "firewall":{
    "group":{
      "network-group":{
        "remote_user_vpn_network":{
          "description":"Remote User VPN subnets",
          "network":[
            "<WIREGUARD_IP_RANGE>/24"
          ]
        }
      }
    }
  },
  "interfaces":{
    "wireguard":{
      "wg0":{
        "description":"VPN for remote clients",
        "address":[
          "<INTERNAL_NETWORK_RANGE>/16"
        ],
        "firewall":{
          "in":{
            "name":"LAN_IN"
          },
          "local":{
            "name":"LAN_LOCAL"
          },
          "out":{
            "name":"LAN_OUT"
          }
        },
        "listen-port":"443",
        "mtu":"1492",
        "peer":[
          {
            "<CLIENT_PUBLIC_KEY>":{
              "allowed-ips":[
                "<CLIENT_IP>/32"
              ],
              "persistent-keepalive":25
            }
          }
        ],
        "private-key":"/config/auth/wireguard/wg_private.key",
        "route-allowed-ips":"false"
      }
    }
  }
}
```

Be sure to fill in the following variables:

```
WIREGUARD_IP_RANGE - The network range being used by the VPN for clients
INERNAL_NETWORK_RANGE - All of the internal networks the VPN should be able to reach
CLIENT_PUBLIC_KEY - The public key which identifies this client (contents of client1_public.key)
CLIENT_IP - The IP that the client should have when connecting with this public key
```

**Note:** if you plan to connect remotely you'll need to portforward `443` for UDP traffic on the `WAN_OUT` firewall rule. This can be done within the controller's interface.

Now you'll need to enter the client configs on your devices:

```
[Interface]
PrivateKey = <client1_private.key>
Address = <CLIENT_IP>/16
DNS = <USG_IP>

[Peer]
PublicKey = <wg_public.key>
Endpoint = <PUBLIC_IP/HOSTNAME>:443
AllowedIPs = 0.0.0.0/0
```

_Alternativly_ you can create that configuration file on the server and save it as `client.conf`. Then use `qrencode -t ansi client.conf` to print out the config to QR which can easily be scanned by most wireguard apps. Note you'll need to install qrencode on the usg with `apt-get install qrencode`, provided you have the repo setup as seen in the custom config section.

Once you connect to the VPN should see that your internal IP is the one specified by the wireguard VPN and your public IP is the one of your USG.


# Firmware updates

When updating everything in the `/opt` directory will be reset and all applications will be uninstalled. Before proceeding with the upgrade I recommend backing up your DNScrypt config as well as your wireguard configs in `/config/auth/wireguard`. I should note that the wireguard configs will survive the upgrade but I would recommend backing up everything just in case.

It's okay that the `config.gateway.json` is still customized during the upgrade, this won't break anything. After the upgrade is complete all you need to do is follow the steps for each application above to re-install the application.

# Misc commands

**Renew IP**

```
disconnect interface pppoe2
connect interface pppoe2
```

**Renew DDNS**

```
show dns dynamic status
update dns dynamic interface pppoe2
```

# Questions/suggestions?

Feel free to open an issue! I'll do my best to answer question there.
