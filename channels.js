// MyTV channel list — add a channel by adding one entry.
//   number: channel number shown on screen
//   name / short: display name / short label for the list
//   logo:   optional image URL ("" = show short name)
//   type:   "hls"      → official HLS stream (.m3u8), plays inside MyTV
//           (omitted)  → iframe embed
//   geo:    true       → official stream only available in Germany (works with a German VPN)
//   mode:   "external" → provider blocks embedding; opens its player in a new tab
// Tested from Canada on 2026-10-02.
window.CHANNELS = [
  { number: 1,  name: "Das Erste",    short: "ARD",   type: "hls", url: "https://daserste-live.ard-mcdn.de/daserste/live/hls/int/master.m3u8" },
  { number: 2,  name: "ZDF",          short: "ZDF",   type: "hls", geo: true, url: "https://zdf-hls-15.akamaized.net/hls/live/2016498/de/high/master.m3u8" },
  { number: 3,  name: "tagesschau24", short: "TS24",  type: "hls", url: "https://tagesschau.akamaized.net/hls/live/2020115/tagesschau/tagesschau_1/master.m3u8" },
  { number: 4,  name: "phoenix",      short: "phx",   type: "hls", geo: true, url: "https://zdf-hls-19.akamaized.net/hls/live/2016502/de/high/master.m3u8" },
  { number: 5,  name: "3sat",         short: "3sat",  type: "hls", geo: true, url: "https://zdf-hls-18.akamaized.net/hls/live/2016501/dach/high/master.m3u8" },
  { number: 6,  name: "arte",         short: "arte",  type: "hls", geo: true, url: "https://artesimulcast.akamaized.net/hls/live/2030993/artelive_de/index.m3u8" },
  { number: 7,  name: "ZDFneo",       short: "neo",   type: "hls", geo: true, url: "https://zdf-hls-16.akamaized.net/hls/live/2016499/de/high/master.m3u8" },
  { number: 8,  name: "ZDFinfo",      short: "info",  type: "hls", geo: true, url: "https://zdf-hls-17.akamaized.net/hls/live/2016500/de/high/master.m3u8" },
  { number: 9,  name: "ONE",          short: "ONE",   type: "hls", geo: true, url: "https://mcdn-one.ard.de/ardone/hls/master.m3u8" },
  { number: 10, name: "ARD alpha",    short: "alpha", type: "hls", url: "https://mcdn.br.de/br/fs/ard_alpha/hls/de/master.m3u8" },
  { number: 11, name: "KiKA",         short: "KiKA",  type: "hls", url: "https://kikageohls.akamaized.net/hls/live/2022693/livetvkika_de/master.m3u8" },
  { number: 12, name: "WDR",          short: "WDR",   type: "hls", url: "https://wdrfs247.akamaized.net/hls/live/681509/wdr_msl4_fs247/index.m3u8" },
  { number: 13, name: "NDR",          short: "NDR",   type: "hls", url: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_hh/master.m3u8" },
  { number: 14, name: "BR",           short: "BR",    type: "hls", url: "https://mcdn.br.de/br/fs/bfs_sued/hls/de/master.m3u8" },
  { number: 15, name: "hr",           short: "HR",    type: "hls", url: "https://hrhls.akamaized.net/hls/live/2024525/hrhls/master.m3u8" },
  { number: 16, name: "SR",           short: "SR",    type: "hls", url: "https://srfs.akamaized.net/hls/live/689649/srfsgeo/index.m3u8" },
  { number: 17, name: "MDR",          short: "MDR",   type: "hls", geo: true, url: "https://mdrtvsnhls.akamaized.net/hls/live/2016928/mdrtvsn/master.m3u8" },
  { number: 18, name: "SWR",          short: "SWR",   type: "hls", geo: true, url: "https://swrbwd-hls.akamaized.net/hls/live/2018672/swrbwd/master.m3u8" },
  { number: 19, name: "rbb",          short: "rbb",   type: "hls", geo: true, url: "https://rbb-hls-berlin.akamaized.net/hls/live/2017824/rbb_berlin/master.m3u8" },
  // Private channels: no embeddable stream → open provider player in a new tab
  { number: 20, name: "RTL",          short: "RTL",   mode: "external", url: "https://www.livehdtv.net/embed/rtl-germany/" },
  { number: 21, name: "SAT.1",        short: "SAT.1", mode: "external", url: "https://www.livehdtv.net/embed/sat-1-germany/" },
  { number: 22, name: "ProSieben",    short: "PRO7",  mode: "external", url: "https://www.livehdtv.net/embed/pro7/" },
  { number: 23, name: "VOX",          short: "VOX",   mode: "external", url: "https://www.livehdtv.net/embed/vox/" },
  { number: 24, name: "kabel eins",   short: "kab1",  mode: "external", url: "https://www.livehdtv.net/embed/kabel-1/" },
  { number: 25, name: "RTLZWEI",      short: "RTL2",  mode: "external", url: "https://www.livehdtv.net/embed/rtl2/" }
];
