export const ENV = process.env.ENV;
export const VITE_PUBLIC_POSTHOG_PROJECT_TOKEN = "phc_kNqjc35bdtVeLNPhvcCM6MWgxVHwDAe4cZ8EYxJ85P9v";
export const VITE_PUBLIC_POSTHOG_HOST = "https://us.i.posthog.com";
export const TASKTRACE_GITHUB_REPO_URL = 'https://github.com/warrenronsiek/TaskTrace';
const prodMacDownloadUrl = "https://tasktrace.com/desktop/TaskTrace-macOS.dmg";
const devMacDownloadUrl = "https://dev.tasktrace.com/desktop/TaskTrace-macOS.dmg";

export const macDownloadUrl =
  ENV === 'prod'
    ? prodMacDownloadUrl
    : devMacDownloadUrl;
