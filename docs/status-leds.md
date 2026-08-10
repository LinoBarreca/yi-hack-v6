# Status LEDs that tell you what the camera is doing

## Why did I change this

A camera has no screen. When it doesn't come online, the only question you can
actually answer from across the room is *"did it get anywhere at all?"* — and
until now the LED couldn't answer it.

The status LED used to be driven only by the original Xiaomi software, which
starts late in the boot. Everything before that — powering up, joining Wi-Fi,
mounting the network share — happened with the camera completely dark. That's the
part that can take the longest, and it's exactly the part that goes wrong: the
wrong Wi-Fi password, a share that moved, a router that hasn't come back yet. A
camera stuck on any of those looked identical to one that was simply dead.

Worse, in the new v6 video mode the original software isn't running at all, so the
LED never lit up, ever.

Now the firmware drives the LED itself, from the first seconds of boot, and each
stage looks different.

## What you get

The LED lights up within a couple of seconds of power-on and then changes as the
camera makes progress, so you can tell how far it got just by looking:

| What you see | What it means |
| --- | --- |
| **Yellow, blinking quickly** | Starting up, no network yet — joining Wi-Fi. |
| **Blue, blinking quickly** | On the network, finishing startup (share, recording, streaming). |
| **Blue, steady** | Up and running. Everything started. |
| **Pale cyan, blinking slowly** (both colours together) | **Recovery mode** — the camera is up but has no firmware payload. Open its web address to fix it. |
| **Off** | Either you switched the LED off (see below), or the camera has no power. |

Two things worth knowing:

- **If it stays yellow**, the camera never got on the network. That's a Wi-Fi
  problem — wrong password, out of range, or the router isn't up yet. This is the
  state where the LED matters most: with no network there is no web interface and
  no app to ask, so the light is the only thing that can tell you the camera is
  alive and where it stopped.
- **Both LEDs share a single window** in the case, so when both are lit you see one
  pale cyan light rather than two separate dots. That's why recovery uses a slow
  blink of both rather than trying to alternate colours.

If the camera is in the original (stock) video mode, the firmware hands the LED
back to the Xiaomi software once boot is finished, so from then on it behaves
exactly as it always did.

## How to set it up

Nothing to set up — the boot stages are automatic.

The **status LED** switch in the web interface (**Camera** page) and in Home
Assistant still does what it always did: turn the LED off once the camera is
running, for anyone who doesn't want a light on in a bedroom or reflecting off a
window at night.

The boot stages are shown regardless of that switch. They're diagnostics, not
decoration — a camera that stays dark while it starts is indistinguishable from
one that isn't starting at all, which is the problem this solves in the first
place. Once startup finishes, the switch is honoured and the LED goes dark.

> In the new v6 video mode, changing the switch currently takes effect at the next
> reboot rather than immediately.
