// MyTV channel list — add a channel by adding one entry.
// number: channel number shown on screen
// name:   display name
// logo:   optional image URL (leave "" to show the name as text)
// url:    the provider's official embed URL (loaded in an iframe)
// mode:   "external" = provider blocks third-party embedding → open in its own player window
//         (omit for normal in-page embedding)
window.CHANNELS = [
  {
    number: 1,
    name: "ProSieben",
    short: "PRO7",
    logo: "",
    url: "https://www.livehdtv.net/embed/pro7/",
    mode: "external"
  }
  // ,{ number: 2, name: "RTL", short: "RTL", logo: "", url: "https://..." }
];
