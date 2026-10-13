#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SmartPick_iC - Recipe file validator (offline twin of SP_RecipeMgr.ImportLine)
Target: Yaskawa iC 9226M-EC / iCube Engineer

Replicates the positional parser of 10_Persistence/FB_SP_RecipeMgr.st and adds
the semantic checks the PLC performs implicitly through the GVL array bounds.
Use it on any hand-edited recipe CSV before loading it on the controller.

Usage:
    python3 SP_RecipeCheck.py <file1.csv> [file2.csv ...]

Exit code: 0 = all PASS, 1 = at least one FAIL.
"""

import os
import re
import sys

# ---- System scale (must mirror 01_Common/GVL_SP_Const.st) -------------------
GC_ROBOTS = 4
GC_FEEDS = 8
GC_CAMS = 2
GC_TYPES = 32
GC_SEQ = 8
GC_LAYERS = 4
GC_PATT = 8
GC_PATT_SLOTS = 16
GC_BATCHES = 8

# ---- Record definitions: token count (incl. record tag) and index ranges ----
REC_SPEC = {
    "CONV":     dict(tok=12),
    "FEED":     dict(tok=11),
    "CAM":      dict(tok=12),
    "CAMMAP":   dict(tok=8),
    "PATT":     dict(tok=14),
    "BATCH":    dict(tok=7),
    "BATCHMIX": dict(tok=5),
    "SHARE":    dict(tok=7),
    "SHARER":   dict(tok=8),
}
EXPORT_ORDER = ["CONV", "FEED", "CAM", "CAMMAP", "PATT", "BATCH",
                "BATCHMIX", "SHARE", "SHARER"]


class RecipeCheck:
    """Stateful single-file check (mirrors one ImportLine session)."""

    def __init__(self, path):
        self.path = path
        self.stem = os.path.splitext(os.path.basename(path))[0]
        self.errors = []
        self.warns = []
        self.name = None
        self.header_seen = 0
        self.section_order = []
        self.feeds = {}        # n -> cfg dict
        self.convs = {}
        self.cams = {}
        self.cammaps = {}      # (cam,k) -> cfg
        self.patts = {}
        self.batches = {}
        self.batchmix = {}     # (batch,k) -> (type,cnt)
        self.shares = {}
        self.sharers = {}      # (feed,robot) -> cfg
        self.used_sections = set()

    # ------------------------------------------------------------------ util
    def err(self, ln, msg):
        self.errors.append("line %d: %s" % (ln, msg))

    def warn(self, ln, msg):
        self.warns.append("line %d: %s" % (ln, msg))

    @staticmethod
    def num(tok, ln, field, where):
        try:
            return float(tok)
        except ValueError:
            raise ValueError("%s field %s: '%s' is not a number" %
                             (where, field, tok))

    @staticmethod
    def int_(tok, ln, field, where):
        try:
            return int(float(tok))
        except ValueError:
            raise ValueError("%s field %s: '%s' is not an integer" %
                             (where, field, tok))

    def check_range(self, v, lo, hi, ln, field, where):
        if v < lo or v > hi:
            self.err(ln, "%s field %s = %s outside [%s..%s]" %
                     (where, field, v, lo, hi))

    # ------------------------------------------------------------------ main
    def run(self):
        with open(self.path, "rb") as fh:
            raw = fh.read()

        if raw.startswith(b"\xef\xbb\xbf"):
            self.err(0, "UTF-8 BOM found: the controller parser would not "
                        "recognize the header. Save as plain ASCII/UTF-8 "
                        "without BOM.")
        try:
            text = raw.decode("ascii")
        except UnicodeDecodeError:
            self.err(0, "Non-ASCII characters found (parser is ASCII-only).")
            text = raw.decode("utf-8", "replace")

        lines = text.split("\n")
        if lines and lines[-1] == "":
            lines.pop()

        for ln_no, line in enumerate(lines, start=1):
            line = line.rstrip("\r")
            if len(line) > 200:
                self.err(ln_no, "Line is %d chars; SP_FileIo/RecipeMgr use "
                                "STRING(200): max 200." % len(line))
            if line.strip() == "":
                self.warn(ln_no, "Empty line (ignored by the importer, but "
                                 "remove it for cleanliness).")
                continue
            if line.startswith("#"):
                self.check_header(line, ln_no)
                continue
            try:
                self.check_record(line, ln_no)
            except ValueError as exc:
                self.err(ln_no, str(exc))

        self.check_cross_refs()
        self.check_layout()
        return len(self.errors) == 0

    # --------------------------------------------------------------- header
    def check_header(self, line, ln_no):
        self.header_seen += 1
        if self.header_seen > 1:
            # The ST parser treats ANY '#' line as a header and overwrites
            # the recipe name: silent rename hazard.
            self.err(ln_no, "Second '#'-line found: the importer treats it as "
                            "a header and overwrites sRecipeName. Mid-file "
                            "comments are not allowed.")
        toks = line.split(",")
        if len(toks) < 2:
            self.err(ln_no, "Header needs '#SmartPick_iC Recipe v2,<name>'.")
            return
        if toks[0] == "#SmartPick_iC Recipe v1":
            # v1 files stored angles in RADIANS; since v1.7.0 the PLC
            # rejects them instead of mis-scaling rotations.
            self.err(ln_no, "Legacy v1 header (angles in radians): the "
                            "importer REJECTS it since v1.7.0. Re-export "
                            "the recipe from the HMI (Recipe v2, degrees) "
                            "or convert angle tokens to degrees.")
            return
        if toks[0] != "#SmartPick_iC Recipe v2":
            self.err(ln_no, "Header tag is '%s' (expected "
                            "'#SmartPick_iC Recipe v2'); the importer "
                            "rejects unknown versions with bErr=TRUE."
                      % toks[0])
        name = ",".join(toks[1:])
        self.name = name
        if len(name) > 32:
            self.err(ln_no, "Recipe name longer than 32 chars (sName "
                            "STRING(32)).")
        if name.strip() != self.stem:
            self.warn(ln_no, "Header name '%s' differs from file stem '%s'. "
                             "The HMI load uses sRecipeName, keep them equal."
                      % (name, self.stem))

    # -------------------------------------------------------------- records
    def check_record(self, line, ln_no):
        toks = line.split(",")
        tag = toks[0]
        if tag not in REC_SPEC:
            self.err(ln_no, "Unknown record '%s' (would be REJECTED by "
                            "ImportLine with bErr=TRUE)." % tag)
            return
        spec = REC_SPEC[tag]
        if len(toks) != spec["tok"]:
            self.err(ln_no, "%s: %d tokens found, %d required." %
                     (tag, len(toks), spec["tok"]))
            return
        if tag not in self.used_sections:
            self.used_sections.add(tag)
            self.section_order.append(tag)

        fn = {"CONV": self.rec_conv, "FEED": self.rec_feed, "CAM": self.rec_cam,
              "CAMMAP": self.rec_cammap, "PATT": self.rec_patt,
              "BATCH": self.rec_batch, "BATCHMIX": self.rec_batchmix,
              "SHARE": self.rec_share, "SHARER": self.rec_sharer}
        fn[tag](toks, ln_no)

    def rec_conv(self, t, ln):
        # CONV,<n>,<scale>,<dir>,<maxspd>,<winstart>,<winlen>,
        #       <slowahead>,<stopahead>,<slowf>,<drive>,<anach>
        n = self.int_(t[1], ln, "n", "CONV")
        self.check_range(n, 1, GC_FEEDS, ln, "n", "CONV")
        scale = self.num(t[2], ln, "scale", "CONV")
        if scale <= 0:
            self.err(ln, "CONV %d: encoder scale must be > 0." % n)
        if self.int_(t[3], ln, "dir", "CONV") not in (-1, 0, 1):
            self.err(ln, "CONV %d: dir must be -1/0 (reverse) or 1 (forward)." % n)
        spd = self.num(t[4], ln, "maxspd", "CONV")
        if spd <= 0:
            self.err(ln, "CONV %d: max speed must be > 0." % n)
        ws, wl = self.num(t[5], ln, "winstart", "CONV"), self.num(t[6], ln, "winlen", "CONV")
        if wl <= 0:
            self.err(ln, "CONV %d: window length must be > 0." % n)
        if ws < 0:
            self.err(ln, "CONV %d: window start must be >= 0." % n)
        slowf = self.num(t[9], ln, "slowf", "CONV")
        self.check_range(slowf, 0.05, 1.0, ln, "slowf", "CONV")
        drive = self.int_(t[10], ln, "drive", "CONV")
        self.check_range(drive, 0, 2, ln, "drive (0=Analog,1=ServoAxis,"
                                         "2=External)", "CONV")
        if drive == 0 and self.int_(t[11], ln, "anach", "CONV") == 0:
            self.warn(ln, "CONV %d: Analog drive with analog channel 0 "
                          "(check GVL_SP_Io.grConvDrive mapping)." % n)
        self.convs[n] = dict(scale=scale, spd=spd, ws=ws, wl=wl)

    def rec_feed(self, t, ln):
        # FEED,<n>,<dir>,<winstart>,<winlen>,<pickahead>,<timeout_ms>,
        #       <zbelt>,<dx>,<dy>,<rot>
        n = self.int_(t[1], ln, "n", "FEED")
        self.check_range(n, 1, GC_FEEDS, ln, "n", "FEED")
        if n in self.feeds:
            self.err(ln, "FEED %d duplicated (last one wins on import)." % n)
        if self.int_(t[2], ln, "dir", "FEED") not in (-1, 0, 1):
            self.err(ln, "FEED %d: dir must be -1/0 (reverse) or 1 (forward)." % n)
        wl = self.num(t[4], ln, "winlen", "FEED")
        if wl <= 0:
            self.err(ln, "FEED %d: window length must be > 0." % n)
        pa = self.num(t[5], ln, "pickahead", "FEED")
        if pa < 0:
            self.err(ln, "FEED %d: pick-ahead must be >= 0." % n)
        tmo = self.int_(t[6], ln, "timeout_ms", "FEED")
        if tmo < 100 or tmo > 600000:
            self.warn(ln, "FEED %d: timeout %d ms outside the suggested "
                          "100..600000 range." % (n, tmo))
        rot = self.num(t[10], ln, "rot", "FEED")
        # v1.7.0: rot is in DEGREES. Misalignment compensation stays small;
        # warn outside +/-45 deg and flag possible legacy radians values.
        if abs(rot) > 45.0:
            self.warn(ln, "FEED %d: |rot| = %g deg; keep misalignment angles "
                          "small (alignment compensation, not a flip)."
                      % (n, rot))
        elif 0.0 < abs(rot) <= 6.4:
            self.warn(ln, "FEED %d: rot = %g deg looks like a legacy v1 "
                          "RADIANS value (v1.7.0 expects degrees, e.g. "
                          "15 deg = 15.0)." % (n, rot))
        self.feeds[n] = dict(ws=self.num(t[3], ln, "winstart", "FEED"),
                             wl=wl, pa=pa, tmo=tmo,
                             zb=self.num(t[7], ln, "zbelt", "FEED"),
                             dx=self.num(t[8], ln, "dx", "FEED"),
                             dy=self.num(t[9], ln, "dy", "FEED"), rot=rot)

    def rec_cam(self, t, ln):
        # CAM,<n>,<drv>,<ip>,<port>,<trig>,<trigdist>,<refspd>,
        #     <maxitems>,<thinrad>,<minscore>,<delay_ms>
        # thinrad: 0 = theta in degrees (default), 1 = radians (converted)
        n = self.int_(t[1], ln, "n", "CAM")
        self.check_range(n, 1, GC_CAMS, ln, "n", "CAM")
        if n in self.cams:
            self.err(ln, "CAM %d duplicated." % n)
        drv = self.int_(t[2], ln, "drv", "CAM")
        self.check_range(drv, 0, 3, ln, "drv (0=Simulated,1=Cognex,"
                                       "2=Keyence,3=GenericTCP)", "CAM")
        ip = t[3]
        if drv == 0:
            pass  # simulated: addressing ignored by SP_VisionCam.Configure
        else:
            if not re.match(r"^\d{1,3}(\.\d{1,3}){3}$", ip):
                self.err(ln, "CAM %d: IP '%s' is not a dotted quad." % (n, ip))
            port = self.int_(t[4], ln, "port", "CAM")
            self.check_range(port, 1, 65535, ln, "port", "CAM")
        trig = self.int_(t[5], ln, "trig", "CAM")
        self.check_range(trig, 0, 3, ln, "trig (0=Distance,1=External,"
                                        "2=Interval,3=Manual)", "CAM")
        mi = self.int_(t[8], ln, "maxitems", "CAM")
        if mi > 16:
            self.err(ln, "CAM %d: maxitems %d exceeds GC_VIS_MAX = 16 "
                         "(per-image parse cap)." % (n, mi))
        sc = self.num(t[10], ln, "minscore", "CAM")
        self.check_range(sc, 0.0, 1.0, ln, "minscore", "CAM")
        if trig == 0:
            td = self.num(t[6], ln, "trigdist", "CAM")
            if td <= 0:
                self.err(ln, "CAM %d: Distance trigger needs trigdist > 0." % n)
        self.cams[n] = dict(drv=drv, ip=ip, trig=trig,
                            td=self.num(t[6], ln, "trigdist", "CAM"),
                            rs=self.num(t[7], ln, "refspd", "CAM"))

    def rec_cammap(self, t, ln):
        # CAMMAP,<n>,<k>,<feed>,<ymin>,<ymax>,<trigd>,<refspd>
        c = self.int_(t[1], ln, "cam", "CAMMAP")
        self.check_range(c, 1, GC_CAMS, ln, "cam", "CAMMAP")
        k = self.int_(t[2], ln, "k", "CAMMAP")
        self.check_range(k, 1, GC_FEEDS, ln, "k", "CAMMAP")
        if (c, k) in self.cammaps:
            self.err(ln, "CAMMAP %d/%d duplicated." % (c, k))
        f = self.int_(t[3], ln, "feed", "CAMMAP")
        self.check_range(f, 0, GC_FEEDS, ln, "feed", "CAMMAP")
        ymin, ymax = self.num(t[4], ln, "ymin", "CAMMAP"), self.num(t[5], ln, "ymax", "CAMMAP")
        if ymin > ymax:
            self.err(ln, "CAMMAP %d/%d: ymin > ymax (region would be empty; "
                         "all items dropped)." % (c, k))
        if f > 0 and c in self.cams and self.cams[c]["trig"] == 0:
            td = self.num(t[6], ln, "trigd", "CAMMAP")
            if td <= 0:
                self.warn(ln, "CAMMAP %d/%d: zero trigger distance with "
                              "Distance policy on this feed." % (c, k))
        self.cammaps[(c, k)] = dict(feed=f, ymin=ymin, ymax=ymax)

    def rec_patt(self, t, ln):
        # PATT,<n>,<rows>,<cols>,<dx>,<dy>,<rotstep>,<bx>,<by>,<bth>,
        #      <layers>,<layerh>,<zbase>,<trigdist>
        n = self.int_(t[1], ln, "n", "PATT")
        self.check_range(n, 1, GC_PATT, ln, "n", "PATT")
        if n in self.patts:
            self.err(ln, "PATT %d duplicated." % n)
        rows, cols = self.int_(t[2], ln, "rows", "PATT"), self.int_(t[3], ln, "cols", "PATT")
        if rows < 1 or cols < 1:
            self.err(ln, "PATT %d: rows and cols must be >= 1." % n)
        if rows * cols > GC_PATT_SLOTS:
            self.err(ln, "PATT %d: rows*cols = %d exceeds GC_PATT_SLOTS = %d."
                     % (n, rows * cols, GC_PATT_SLOTS))
        dx, dy = self.num(t[4], ln, "dx", "PATT"), self.num(t[5], ln, "dy", "PATT")
        if rows * cols > 1 and (dx <= 0 or dy <= 0):
            self.err(ln, "PATT %d: slot pitch must be > 0." % n)
        layers = self.int_(t[10], ln, "layers", "PATT")
        self.check_range(layers, 1, GC_LAYERS, ln, "layers", "PATT")
        lh = self.num(t[11], ln, "layerh", "PATT")
        if layers > 1 and lh <= 0:
            self.err(ln, "PATT %d: multi-layer pattern needs layer height > 0."
                     % n)
        self.patts[n] = dict(rows=rows, cols=cols, slots=rows * cols,
                             layers=layers,
                             zd=self.num(t[13], ln, "trigdist", "PATT"))

    def rec_batch(self, t, ln):
        # BATCH,<n>,<outfeed>,<patt>,<qty>,<trig>,<priority>
        n = self.int_(t[1], ln, "n", "BATCH")
        self.check_range(n, 1, GC_BATCHES, ln, "n", "BATCH")
        if n in self.batches:
            self.err(ln, "BATCH %d duplicated." % n)
        of = self.int_(t[2], ln, "outfeed", "BATCH")
        self.check_range(of, 1, GC_FEEDS, ln, "outfeed", "BATCH")
        pt = self.int_(t[3], ln, "patt", "BATCH")
        self.check_range(pt, 1, GC_PATT, ln, "patt", "BATCH")
        if self.int_(t[4], ln, "qty", "BATCH") < 1:
            self.err(ln, "BATCH %d: qty must be >= 1." % n)
        self.check_range(self.int_(t[5], ln, "trig", "BATCH"), 0, 2, ln,
                         "trig (0=Distance,1=Sensor,2=BatchStart)", "BATCH")
        self.check_range(self.int_(t[6], ln, "priority", "BATCH"), -100, 100,
                         ln, "priority", "BATCH")
        self.batches[n] = dict(of=of, patt=pt, qty=self.int_(t[4], ln, "qty", "BATCH"),
                               trig=self.int_(t[5], ln, "trig", "BATCH"))

    def rec_batchmix(self, t, ln):
        # BATCHMIX,<n>,<k>,<type>,<cnt>
        b = self.int_(t[1], ln, "batch", "BATCHMIX")
        self.check_range(b, 1, GC_BATCHES, ln, "batch", "BATCHMIX")
        k = self.int_(t[2], ln, "k", "BATCHMIX")
        self.check_range(k, 1, GC_SEQ, ln, "k", "BATCHMIX")
        if (b, k) in self.batchmix:
            self.err(ln, "BATCHMIX %d/%d duplicated." % (b, k))
        ty = self.int_(t[3], ln, "type", "BATCHMIX")
        self.check_range(ty, 0, GC_TYPES, ln, "type", "BATCHMIX")
        cnt = self.int_(t[4], ln, "cnt", "BATCHMIX")
        if cnt < 0:
            self.err(ln, "BATCHMIX %d/%d: cnt must be >= 0." % (b, k))
        self.batchmix[(b, k)] = (ty, cnt)

    def rec_share(self, t, ln):
        # SHARE,<feed>,<strat>,<match>,<strict>,<pickbias>,<outfeedmap>
        f = self.int_(t[1], ln, "feed", "SHARE")
        self.check_range(f, 1, GC_FEEDS, ln, "feed", "SHARE")
        if f in self.shares:
            self.err(ln, "SHARE %d duplicated." % f)
        self.check_range(self.int_(t[2], ln, "strat", "SHARE"), 0, 3, ln,
                         "strat (0=Organic,1=Greedy,2=Balanced,3=Manual)", "SHARE")
        self.check_range(self.int_(t[3], ln, "match", "SHARE"), 0, 2, ln,
                         "match (0=Matched,1=Unmatched,2=Mixed)", "SHARE")
        if self.int_(t[4], ln, "strict", "SHARE") not in (0, 1):
            self.err(ln, "SHARE %d: strict must be 0 or 1." % f)
        self.check_range(self.num(t[5], ln, "pickbias", "SHARE"), 0.0, 1.0,
                         ln, "pickbias", "SHARE")
        self.check_range(self.int_(t[6], ln, "outfeedmap", "SHARE"), 0,
                         GC_FEEDS, ln, "outfeedmap", "SHARE")
        self.shares[f] = dict(ofm=self.int_(t[6], ln, "outfeedmap", "SHARE"))

    def rec_sharer(self, t, ln):
        # SHARER,<feed>,<robot>,<ratio>,<rangef>,<ranget>,<tmask>,<manual>
        f = self.int_(t[1], ln, "feed", "SHARER")
        self.check_range(f, 1, GC_FEEDS, ln, "feed", "SHARER")
        r = self.int_(t[2], ln, "robot", "SHARER")
        self.check_range(r, 1, GC_ROBOTS, ln, "robot", "SHARER")
        if (f, r) in self.sharers:
            self.err(ln, "SHARER %d/%d duplicated." % (f, r))
        ratio = self.num(t[3], ln, "ratio", "SHARER")
        if ratio <= 0:
            self.err(ln, "SHARER %d/%d: ratio must be > 0 (Configure "
                         "sanitizes to 1.0)." % (f, r))
        rf, rt = self.num(t[4], ln, "rangef", "SHARER"), self.num(t[5], ln, "ranget", "SHARER")
        active = not (rf == 0 and rt == 0)
        if active:
            if rf > rt:
                self.err(ln, "SHARER %d/%d: rangef > ranget (robot never "
                             "eligible; use 0,0 to disable)." % (f, r))
            if rf < 0:
                self.err(ln, "SHARER %d/%d: rangef < 0 (offset domain is "
                             "0..window)." % (f, r))
        mask = self.int_(t[6], ln, "tmask", "SHARER")
        if mask < 0 or mask > 4294967295:
            self.err(ln, "SHARER %d/%d: tmask outside 0..4294967295 "
                         "(UDINT domain)." % (f, r))
        if self.int_(t[7], ln, "manual", "SHARER") not in (0, 1):
            self.err(ln, "SHARER %d/%d: manual must be 0 or 1." % (f, r))
        self.sharers[(f, r)] = dict(ratio=ratio, rf=rf, rt=rt,
                                    mask=mask,
                                    man=self.int_(t[7], ln, "manual", "SHARER"))

    # ------------------------------------------------------------ semantics
    def check_cross_refs(self):
        for b, cfg in sorted(self.batches.items()):
            if cfg["of"] not in self.feeds:
                self.err(0, "BATCH %d: outfeed %d has no FEED record "
                            "(disabled feed)." % (b, cfg["of"]))
            if cfg["patt"] not in self.patts:
                self.err(0, "BATCH %d: pattern %d has no PATT record." %
                         (b, cfg["patt"]))
            # Mix capacity per layer
            total = sum(cnt for (bb, _k), (_ty, cnt) in self.batchmix.items()
                        if bb == b)
            if total > 0:
                if cfg["patt"] in self.patts:
                    slots = self.patts[cfg["patt"]]["slots"]
                    if total > slots:
                        self.err(0, "BATCH %d: mix total %d exceeds pattern "
                                    "%d slots per layer (%d)." %
                                    (b, total, cfg["patt"], slots))
            else:
                self.warn(0, "BATCH %d has no BATCHMIX entries (mix defaults "
                             "to type 0 = unknown)." % b)
        for (c, k), mm in sorted(self.cammaps.items()):
            if mm["feed"] > 0 and mm["feed"] not in self.feeds:
                self.err(0, "CAMMAP %d/%d points to feed %d without FEED "
                            "record." % (c, k, mm["feed"]))
            if mm["feed"] > 0 and c not in self.cams:
                self.err(0, "CAMMAP %d/%d references camera %d without CAM "
                            "record." % (c, k, c))
        for f, sh in sorted(self.shares.items()):
            if sh["ofm"] > 0 and sh["ofm"] not in self.feeds:
                self.err(0, "SHARE %d: outfeed map target %d has no FEED "
                            "record." % (f, sh["ofm"]))
        # Balancer eligibility: every used INFEED needs at least one robot.
        # Outfeeds (targets of the dispatcher outfeed map) are fed by the
        # pattern engine: placement reservations bypass the balancer.
        outfeeds = set(sh["ofm"] for sh in self.shares.values() if sh["ofm"] > 0)
        for f in sorted(self.feeds):
            if f in outfeeds:
                continue
            elig = [r for (ff, r) in self.sharers
                    if ff == f and not (self.sharers[(ff, r)]["rf"] == 0
                                        and self.sharers[(ff, r)]["rt"] == 0)]
            if not elig:
                self.warn(0, "FEED %d used but no robot has a work range on "
                             "it (all SHARER ranges 0,0)." % f)

    def check_layout(self):
        # Section order (warning only; import is order independent)
        idx = [EXPORT_ORDER.index(s) for s in self.section_order
               if s in EXPORT_ORDER]
        if idx != sorted(idx):
            self.warn(0, "Record order differs from the PLC export order "
                         "(%s). Import still works positionally." %
                      ", ".join(EXPORT_ORDER))
        # Real-mode coverage: infeeds without any camera region. Outfeeds
        # receive placement targets from the pattern engine, not cameras.
        cam_feeds = set(mm["feed"] for mm in self.cammaps.values()
                        if mm["feed"] > 0 and mm["feed"] in self.feeds)
        outfeeds = set(sh["ofm"] for sh in self.shares.values() if sh["ofm"] > 0)
        sim = any(c["drv"] == 0 for c in self.cams.values())
        for f in sorted(self.feeds):
            if f in cam_feeds or f in outfeeds:
                continue
            if sim:
                self.warn(0, "FEED %d has no camera region (OK in "
                             "simulation: items injected via "
                             "InjectItem)." % f)
            else:
                self.warn(0, "FEED %d has no camera region: in real mode "
                             "no items will ever be tracked on it." % f)
        # Chained outfeed mapping is ignored by the dispatcher: flag only a
        # target that itself maps further on.
        for f, sh in sorted(self.shares.items()):
            if sh["ofm"] > 0 and sh["ofm"] in self.shares \
               and self.shares[sh["ofm"]]["ofm"] > 0:
                self.warn(0, "SHARE %d maps to outfeed %d which itself has "
                             "an outfeed map (chained mapping is ignored by "
                             "the dispatcher)." % (f, sh["ofm"]))

    # -------------------------------------------------------------- report
    def report(self):
        print("=" * 72)
        print("FILE : %s" % self.path)
        if self.name:
            print("NAME : %s" % self.name)
        counts = {
            "CONV": len(self.convs), "FEED": len(self.feeds),
            "CAM": len(self.cams), "CAMMAP": len(self.cammaps),
            "PATT": len(self.patts), "BATCH": len(self.batches),
            "BATCHMIX": len(self.batchmix), "SHARE": len(self.shares),
            "SHARER": len(self.sharers),
        }
        print("OBJECTS: " + "  ".join("%s=%d" % kv for kv in counts.items()))
        for w in self.warns:
            print("  WARN : %s" % w)
        for e in self.errors:
            print("  ERROR: %s" % e)
        print("RESULT: %s" % ("PASS" if not self.errors else "FAIL"))
        print("=" * 72)
        return not self.errors


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    ok = True
    for path in argv[1:]:
        chk = RecipeCheck(path)
        ok = chk.run() and ok
        chk.report()
    print("\nOverall: %s" % ("ALL PASS" if ok else "FAILURES FOUND"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
