# Problem Statement (200 words)

When disaster strikes, **the network is the first thing that fails**.
During the July Revolution in Bangladesh, cellular shutdowns and throttled
2G links made it impossible to ask for blood, find a missing relative, or
confirm whether a hospital was open. Citizens turned to ad-hoc "Jogajog"
relays — neighbors texting neighbors — but the messages were unauthenticated
and the same life-saving rumors got distorted into life-threatening panic.

The Crisis Tech track names this exact failure: technology that **works
when normal infrastructure fails**.

The people most affected are ordinary citizens in low-bandwidth, low-trust
environments: a volunteer carrying a phone through a flooded neighborhood,
a community moderator trying to verify a safe-route bulletin, a hospital
coordinator confirming a plasma donor. They have intermittent electricity,
intermittent connectivity, and phones that are often two generations old.
Anything that requires a stable HTTPS handshake to a single central server
will not reach them.

Today, there is no open-source system that simultaneously (a) lets a citizen
post an emergency request from an offline phone, (b) hands that request to a
trusted moderator who can cryptographically sign it, and (c) syncs every
participant when any one of them briefly touches the network. **TruthRelay
fills that gap.**