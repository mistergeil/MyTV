// MyTV channel list — add a channel by adding one entry.
//   number: channel number shown on screen
//   name / short: display name / short label for the list
//   logo:   optional image URL ("" = show short name)
//   type:   "hls"      → official HLS stream (.m3u8), plays inside MyTV
//           (omitted)  → iframe embed
//   mode:   "external" → provider blocks embedding; opens its player in a new tab
// HLS streams tested from Canada on 2026-10-02 (ZDF, 3sat, phoenix, arte, ONE, MDR, SWR, rbb are geo-blocked).
window.CHANNELS = [
  { number: 1,  name: "Das Erste",     short: "ARD",   logo: "", type: "hls", url: "https://daserste-live.ard-mcdn.de/daserste/live/hls/int/master.m3u8" },
  { number: 2,  name: "tagesschau24",  short: "TS24",  logo: "", type: "hls", url: "https://tagesschau.akamaized.net/hls/live/2020115/tagesschau/tagesschau_1/master.m3u8" },
  { number: 3,  name: "WDR",           short: "WDR",   logo: "", type: "hls", url: "https://wdrfs247.akamaized.net/hls/live/681509/wdr_msl4_fs247/index.m3u8" },
  { number: 4,  name: "NDR Hamburg",   short: "NDR",   logo: "", type: "hls", url: "https://mcdn.ndr.de/ndr/hls/ndr_fs/ndr_hh/master.m3u8" },
  { number: 5,  name: "BR Süd",        short: "BR",    logo: "", type: "hls", url: "https://mcdn.br.de/br/fs/bfs_sued/hls/de/master.m3u8" },
  { number: 6,  name: "hr",            short: "HR",    logo: "", type: "hls", url: "https://hrhls.akamaized.net/hls/live/2024525/hrhls/master.m3u8" },
  { number: 7,  name: "SR",            short: "SR",    logo: "", type: "hls", url: "https://srfs.akamaized.net/hls/live/689649/srfsgeo/index.m3u8" },
  { number: 8,  name: "ARD alpha",     short: "alpha", logo: "", type: "hls", url: "https://mcdn.br.de/br/fs/ard_alpha/hls/de/master.m3u8" },
  { number: 9,  name: "KiKA",          short: "KiKA",  logo: "", type: "hls", url: "https://kikageohls.akamaized.net/hls/live/2022693/livetvkika_de/master.m3u8" },
  { number: 10, name: "ProSieben",     short: "PRO7",  logo: "", mode: "external", url: "https://www.livehdtv.net/embed/pro7/" }
];
