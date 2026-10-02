// MyTV channel list — add a channel by adding one entry.
//   number: channel number shown on screen
//   name / short: display name / short label for the list
//   logo:   optional image URL ("" = show short name)
//   type:   "hls"      → official HLS stream (.m3u8), plays inside MyTV
//           (omitted)  → iframe embed
//   geo:    true / "CH" → official stream only available in Germany / Switzerland (works with a VPN there)
//   epg:    channel id in the ARD program API (programm-api.ard.de) → program guide
//   xmltv:  channel id in epg.json (built every 6 h by .github/workflows/epg.yml from epgshare01)
//   mode:   "external" → provider blocks embedding; opens its player in a new tab
// Tested from Canada on 2026-10-02.
window.CHANNELS = [
  { number: 1,  name: "Das Erste",    short: "ARD",   type: "hls", epg: "daserste", url: "https://daserste-live.ard-mcdn.de/daserste/live/hls/int/master.m3u8" },
  { number: 2,  name: "ZDF",          short: "ZDF",   type: "hls", geo: true, xmltv: "ZDF.de", url: "https://zdf-hls-15.akamaized.net/hls/live/2016498/de/high/master.m3u8" },
  { number: 3,  name: "tagesschau24", short: "TS24",  type: "hls", epg: "tagesschau24", url: "https://tagesschau.akamaized.net/hls/live/2020115/tagesschau/tagesschau_1/master.m3u8" },
  { number: 4,  name: "phoenix",      short: "phx",   type: "hls", geo: true, epg: "phoenix", url: "https://zdf-hls-19.akamaized.net/hls/live/2016502/de/high/master.m3u8" },
  { number: 5,  name: "3sat",         short: "3sat",  type: "hls", geo: true, epg: "3sat", url: "https://zdf-hls-18.akamaized.net/hls/live/2016501/dach/high/master.m3u8" },
  { number: 6,  name: "arte",         short: "arte",  type: "hls", geo: true, epg: "arte", url: "https://artesimulcast.akamaized.net/hls/live/2030993/artelive_de/index.m3u8" },
  { number: 7,  name: "ZDFneo",       short: "neo",   type: "hls", geo: true, xmltv: "ZDFneo.de", url: "https://zdf-hls-16.akamaized.net/hls/live/2016499/de/high/master.m3u8" },
  { number: 8,  name: "ZDFinfo",      short: "info",  type: "hls", geo: true, xmltv: "ZDFinfo.de", url: "https://zdf-hls-17.akamaized.net/hls/live/2016500/de/high/master.m3u8" },
  { number: 9,  name: "ONE",          short: "ONE",   type: "hls", geo: true, epg: "one", url: "https://mcdn-one.ard.de/ardone/hls/master.m3u8" },
  { number: 10, name: "ARD alpha",    short: "alpha", type: "hls", epg: "alpha", url: "https://mcdn.br.de/br/fs/ard_alpha/hls/de/master.m3u8" },
  { number: 11, name: "KiKA",         short: "KiKA",  type: "hls", epg: "kika", url: "https://kikageohls.akamaized.net/hls/live/2022693/livetvkika_de/master.m3u8" },
  { number: 12, name: "WDR",          short: "WDR",   type: "hls", epg: "wdr", url: "https://wdrfs247.akamaized.net/hls/live/681509/wdr_msl4_fs247/index.m3u8" },
  { number: 13, name: "NDR",          short: "NDR",   type: "hls", epg: "ndr", url: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_hh/master.m3u8" },
  { number: 14, name: "BR",           short: "BR",    type: "hls", epg: "br", url: "https://mcdn.br.de/br/fs/bfs_sued/hls/de/master.m3u8" },
  { number: 15, name: "hr",           short: "HR",    type: "hls", epg: "hr", url: "https://hrhls.akamaized.net/hls/live/2024525/hrhls/master.m3u8" },
  { number: 16, name: "SR",           short: "SR",    type: "hls", epg: "sr", url: "https://srfs.akamaized.net/hls/live/689649/srfsgeo/index.m3u8" },
  { number: 17, name: "MDR",          short: "MDR",   type: "hls", geo: true, epg: "mdr", url: "https://mdrtvsnhls.akamaized.net/hls/live/2016928/mdrtvsn/master.m3u8" },
  { number: 18, name: "SWR",          short: "SWR",   type: "hls", geo: true, epg: "swr", url: "https://swrbwd-hls.akamaized.net/hls/live/2018672/swrbwd/master.m3u8" },
  { number: 19, name: "rbb",          short: "rbb",   type: "hls", geo: true, epg: "rbb", url: "https://rbb-hls-berlin.akamaized.net/hls/live/2017824/rbb_berlin/master.m3u8" },
  // Private channels: no embeddable stream → open provider player in a new tab
  { number: 20, name: "RTL",          short: "RTL",   mode: "external", xmltv: "RTL.de", url: "https://www.livehdtv.net/embed/rtl-germany/" },
  { number: 21, name: "SAT.1",        short: "SAT.1", mode: "external", xmltv: "SAT.1.de", url: "https://www.livehdtv.net/embed/sat-1-germany/" },
  { number: 22, name: "ProSieben",    short: "PRO7",  mode: "external", xmltv: "ProSieben.de", url: "https://www.livehdtv.net/embed/pro7/" },
  { number: 23, name: "VOX",          short: "VOX",   mode: "external", xmltv: "VOX.de", url: "https://www.livehdtv.net/embed/vox/" },
  { number: 24, name: "kabel eins",   short: "kab1",  mode: "external", xmltv: "kabel.eins.de", url: "https://www.livehdtv.net/embed/kabel-1/" },
  { number: 25, name: "RTLZWEI",      short: "RTL2",  mode: "external", xmltv: "RTLZWEI.de", url: "https://www.livehdtv.net/embed/rtl2/" },
  { number: 26, name: "ProSieben MAXX", short: "MAXX", mode: "external", xmltv: "ProSieben.MAXX.de", url: "https://www.livehdtv.net/embed/prosieben-maxx/" },
  { number: 27, name: "SAT.1 Gold", short: "Gold", mode: "external", xmltv: "SAT.1.Gold.de", url: "https://www.livehdtv.net/embed/sat1-gold/" },
  { number: 28, name: "sixx", short: "sixx", mode: "external", xmltv: "sixx.de", url: "https://www.livehdtv.net/embed/sixx/" },
  { number: 29, name: "kabel eins Doku", short: "k1Dok", mode: "external", xmltv: "kabel.eins.Doku.de", url: "https://www.livehdtv.net/embed/kabel-1-doku/" },
  { number: 30, name: "Super RTL", short: "SRTL", mode: "external", xmltv: "SUPER.RTL.de", url: "https://www.livehdtv.net/embed/super-rtl/" },
  { number: 31, name: "RTL Nitro", short: "Nitro", mode: "external", xmltv: "NITRO.de", url: "https://www.livehdtv.net/embed/rtl-nitro/" },
  { number: 32, name: "n-tv", short: "n-tv", mode: "external", xmltv: "ntv.de", url: "https://www.livehdtv.net/embed/ntv-german/" },
  { number: 33, name: "WELT", short: "WELT", mode: "external", xmltv: "WELT.de", url: "https://www.livehdtv.net/embed/welt/" },
  { number: 34, name: "Tele 5", short: "Tele5", mode: "external", xmltv: "Tele.5.de", url: "https://www.livehdtv.net/embed/tele-5-germany/" },
  { number: 35, name: "DMAX", short: "DMAX", mode: "external", xmltv: "DMAX.de", url: "https://www.livehdtv.net/embed/dmax-germany/" },
  { number: 36, name: "TLC", short: "TLC", mode: "external", xmltv: "TLC.de", url: "https://www.livehdtv.net/embed/tlc-germany/" },
  { number: 37, name: "Comedy Central", short: "CC", mode: "external", xmltv: "Comedy.Central.de", url: "https://www.livehdtv.net/embed/comedy-central-germany/" },
  { number: 38, name: "Disney Channel", short: "Disny", mode: "external", xmltv: "Disney.Channel.de", url: "https://www.livehdtv.net/embed/disney-channel-germany/" },
  { number: 39, name: "Nickelodeon", short: "Nick", mode: "external", xmltv: "nick.de", url: "https://www.livehdtv.net/embed/ch474/" },
  { number: 40, name: "DW Deutsch", short: "DW", mode: "external", url: "https://www.livehdtv.net/embed/dw-deutsche-welle-deutsch/" },
  // Switzerland
  { number: 41, name: "SRF 1",       short: "SRF1",  mode: "external", xmltv: "SRF.1.ch", url: "https://www.livehdtv.net/embed/srf-1/" },
  { number: 42, name: "RTS 1",       short: "RTS1",  mode: "external", xmltv: "RTS.1.ch", url: "https://www.livehdtv.net/embed/rts-1-switzerland/" },
  { number: 43, name: "RTS Info",    short: "RTSi",  type: "hls", geo: "CH", url: "https://rtsinfo-d.akamaized.net/out/v1/2b7ae2e1ba3f43c6aba15bced153baf5/index.m3u8" },
  { number: 44, name: "Tele 1",      short: "Tele1", mode: "external", xmltv: "Tele.1.ch", url: "https://www.livehdtv.net/embed/tele-1-switzerland/" },
  { number: 45, name: "TeleTicino",  short: "TTi",   type: "hls", xmltv: "Tele.Ticino.ch", url: "https://vstream-cdn.ch/hls/teleticino.m3u8" },
  { number: 46, name: "Canal Alpha", short: "Alpha", type: "hls", url: "https://canalalphaju.vedge.infomaniak.com/livecast/ik:canalalphaju/playlist.m3u8" },
  { number: 47, name: "Canal 9",     short: "C9",    type: "hls", geo: "CH", xmltv: "Canal.9.ch", url: "https://livehd.vedge.infomaniak.com/livecast/livehd/master.m3u8" }
];
