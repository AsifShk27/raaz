# Reddit API notes (listings + OAuth)

Listings used by the trend scout:
- `/r/{subreddit}/hot.json`
- `/r/{subreddit}/new.json`
- `/r/{subreddit}/rising.json`
- `/r/{subreddit}/top.json?t=day|week|month|year|all`
- `/r/all/<sort>.json` and `/r/popular/<sort>.json` work the same way
- `/subreddits/popular.json` and `/subreddits/new.json` for discovery

OAuth basics:
- Access token endpoint: `https://www.reddit.com/api/v1/access_token`
- Authenticated API base: `https://oauth.reddit.com`
- Use `client_credentials` for app-only or `refresh_token` for user-scoped access

Operational tips:
- Set a descriptive `User-Agent` string.
- Respect rate limits and subreddit rules; keep scan sizes conservative.

Sources:
- https://www.reddit.com/dev/api/
- https://github.com/reddit-archive/reddit/wiki/OAuth2
