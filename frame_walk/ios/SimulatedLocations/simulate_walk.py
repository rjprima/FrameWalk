#!/usr/bin/env python3
"""Walks the booted iOS Simulator along a GPX file, without Xcode.

Xcode can only play a GPX file while it is debugging the app, so this drives
the simulator with `xcrun simctl location` instead, which also works with
`flutter run`. Each leg between named waypoints (the stops) is walked at
--speed, with a pause at each stop.

    python3 ios/SimulatedLocations/simulate_walk.py \
        ios/SimulatedLocations/red_square_walk.gpx

Ctrl+C stops the walk and leaves the simulator where it is.
"""

import argparse
import math
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

NS = {"gpx": "http://www.topografix.com/GPX/1/1"}


def distance_m(a, b):
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dlat, dlon = lat2 - lat1, math.radians(b[1] - a[1])
    h = (math.sin(dlat / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 2 * 6371000 * math.asin(math.sqrt(h))


def load_legs(path):
    """Splits the waypoints into legs that each end at a named stop."""
    legs, leg, names = [], [], []
    for wpt in ET.parse(path).getroot().findall("gpx:wpt", NS):
        point = (float(wpt.get("lat")), float(wpt.get("lon")))
        if not leg or leg[-1] != point:
            leg.append(point)
        name = wpt.findtext("gpx:name", namespaces=NS)
        if name:
            legs.append(leg)
            names.append(name)
            leg = [point]
    return legs, names


def simctl(device, *args):
    subprocess.run(["xcrun", "simctl", "location", device, *args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("gpx")
    parser.add_argument("--device", default="booted")
    parser.add_argument("--speed", type=float, default=1.4,
                        help="walking speed in m/s (default 1.4)")
    parser.add_argument("--pause", type=float, default=15,
                        help="seconds to stay at each stop (default 15)")
    args = parser.parse_args()

    legs, names = load_legs(args.gpx)
    if not legs:
        sys.exit("No named waypoints found in " + args.gpx)

    # The first leg is just the starting stop.
    start = legs[0][-1]
    simctl(args.device, "set", f"{start[0]},{start[1]}")
    print(f"At {names[0]}. Waiting {args.pause:.0f} s.")
    time.sleep(args.pause)

    for leg, name in zip(legs[1:], names[1:]):
        meters = sum(distance_m(a, b) for a, b in zip(leg, leg[1:]))
        seconds = meters / args.speed
        print(f"Walking to {name}: {meters:.0f} m, about {seconds:.0f} s.")
        simctl(args.device, "start", f"--speed={args.speed}", "--distance=5",
               *(f"{lat},{lon}" for lat, lon in leg))
        time.sleep(seconds + 1)
        end = leg[-1]
        simctl(args.device, "set", f"{end[0]},{end[1]}")
        print(f"At {name}. Waiting {args.pause:.0f} s.")
        time.sleep(args.pause)

    print("Walk finished.")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nStopped.")
