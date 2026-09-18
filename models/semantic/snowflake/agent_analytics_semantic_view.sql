{# Snowflake semantic view over the three daily fact tables, for Cortex Analyst and
   any other natural-language consumer.

   The `semantic_view` materialization comes from Snowflake-Labs/dbt_semantic_view --
   a prerequisite, not a declared dependency; see require_semantic_view_package().

   Clause order is fixed by Snowflake: TABLES, RELATIONSHIPS, FACTS, DIMENSIONS,
   METRICS. Every fact table joins to a conformed dimension rather than to another
   fact table: RELATIONSHIPS is many-to-one, so a direct fact-to-fact join would drop
   rows on the "one" side and repeat its measures across the "many" side. #}
{{
  config(
    materialized='semantic_view',
    enabled=(var('enable_semantic_views', false) and target.type == 'snowflake')
  )
}}

{{ require_semantic_view_package() }}

TABLES (
  dates AS {{ ref('dim_date') }}
    PRIMARY KEY (event_date)
    WITH SYNONYMS ('date', 'day', 'calendar')
    COMMENT = 'One row per day on which any traffic was recorded.',

  pages AS {{ ref('dim_page') }}
    PRIMARY KEY (page_url_host_path)
    WITH SYNONYMS ('page', 'url', 'content')
    COMMENT = 'One row per page, keyed on host+path.',

  operators AS {{ ref('dim_operator') }}
    PRIMARY KEY (operator)
    WITH SYNONYMS ('operator', 'company', 'vendor', 'ai company')
    COMMENT = 'One row per organisation operating an agent, e.g. OpenAI, Anthropic, Google.',

  {# No PRIMARY KEY: agent_purpose is nullable, and nothing references this table. #}
  agent_traffic AS {{ ref('agent_pageviews_daily') }}
    WITH SYNONYMS ('agent traffic', 'bot traffic', 'crawler traffic', 'ai crawlers')
    COMMENT = 'Daily agent/crawler page requests, by agent, operator, purpose, source channel and page.',

  human_traffic AS {{ ref('human_pageviews_daily') }}
    PRIMARY KEY (event_date, page_url_host_path)
    WITH SYNONYMS ('human pageviews', 'people', 'real users', 'pageviews')
    COMMENT = 'Daily human page views per page. Excludes all bot-flagged traffic.',

  referrals AS {{ ref('human_referrals_daily') }}
    PRIMARY KEY (event_date, referring_operator, page_url_host_path)
    WITH SYNONYMS ('referrals', 'ai referrals', 'traffic from ai', 'citations')
    COMMENT = 'Daily human page views arriving from an AI product, attributed to the operator behind it.'
)

RELATIONSHIPS (
  agent_traffic_to_date AS agent_traffic (event_date) REFERENCES dates,
  agent_traffic_to_page AS agent_traffic (page_url_host_path) REFERENCES pages,
  agent_traffic_to_operator AS agent_traffic (agent_operator) REFERENCES operators,

  human_traffic_to_date AS human_traffic (event_date) REFERENCES dates,
  human_traffic_to_page AS human_traffic (page_url_host_path) REFERENCES pages,

  referrals_to_date AS referrals (event_date) REFERENCES dates,
  referrals_to_page AS referrals (page_url_host_path) REFERENCES pages,
  referrals_to_operator AS referrals (referring_operator) REFERENCES operators
)

FACTS (
  agent_traffic.hits AS hits
    COMMENT = 'Agent requests on one day for one agent/operator/purpose/channel/page combination.',
  {# A metric can only reference expressions on its own logical table, so
     COUNT(DISTINCT ...) over page/operator needs local facts to count. #}
  agent_traffic.crawled_page AS page_url_host_path
    COMMENT = 'Page hit by this agent request.',
  agent_traffic.crawling_operator AS agent_operator
    COMMENT = 'Operator behind this agent request.',
  human_traffic.human_pageviews AS human_pageviews
    COMMENT = 'Human page views on one day for one page.',
  referrals.referred_pageviews AS referred_pageviews
    COMMENT = 'AI-referred human page views on one day for one operator and page.',
  referrals.referred_sessions AS referred_sessions
    COMMENT = 'Distinct sessions behind those referred page views. Exact within a day; summing across days over-counts sessions that span midnight.'
)

DIMENSIONS (
  dates.event_date AS event_date
    WITH SYNONYMS ('date', 'day')
    COMMENT = 'The day the traffic occurred.',
  dates.week_start_date AS week_start_date
    WITH SYNONYMS ('week') COMMENT = 'Monday of the week the traffic occurred.',
  dates.month_start_date AS month_start_date
    WITH SYNONYMS ('month') COMMENT = 'First day of the month the traffic occurred.',
  dates.quarter_start_date AS quarter_start_date
    WITH SYNONYMS ('quarter') COMMENT = 'First day of the quarter.',
  dates.year_start_date AS year_start_date
    WITH SYNONYMS ('year') COMMENT = 'First day of the year.',

  pages.page_url_host_path AS page_url_host_path
    WITH SYNONYMS ('page', 'url', 'page url')
    COMMENT = 'Host and path concatenated, without scheme or query string. ''unknown'' when the URL was missing.',
  pages.page_host AS page_host
    WITH SYNONYMS ('host', 'domain', 'site') COMMENT = 'Host portion of the page URL.',
  pages.page_path AS page_path
    WITH SYNONYMS ('path', 'slug') COMMENT = 'Path portion of the page URL, leading slash included.',
  pages.page_section AS page_section
    WITH SYNONYMS ('section', 'area', 'top level path')
    COMMENT = 'First path segment, e.g. ''docs'' for /docs/setup. Empty string at the site root.',

  operators.operator AS operator
    WITH SYNONYMS ('operator', 'company', 'vendor')
    COMMENT = 'Organisation operating the agent. ''unknown'' when classification was unavailable.',
  operators.has_referral_sources AS has_referral_sources
    COMMENT = 'False means no referral sources are configured for this operator, so its referral metrics will read zero regardless of reality. Mention this caveat when reporting zero referrals.',
  operators.is_known_non_referring AS is_known_non_referring
    COMMENT = 'True for operators documented as never sending referral traffic. Zero referrals is the expected answer, not a data gap.',

  agent_traffic.agent_name AS agent_name
    WITH SYNONYMS ('agent', 'bot', 'crawler', 'user agent')
    COMMENT = 'Canonical agent identity, e.g. GPTBot, ClaudeBot, Googlebot.',
  agent_traffic.agent_purpose AS agent_purpose
    WITH SYNONYMS ('purpose', 'why', 'reason')
    COMMENT = 'Why the agent fetched the page: AI_TRAINING, AI_USER_FETCH, AI_SEARCH_INDEX, SEARCH_INDEX, or NULL when unclassified.',
  agent_traffic.purpose_group AS purpose_group
    WITH SYNONYMS ('purpose group', 'category')
    COMMENT = 'Coarse grouping of agent_purpose: AI, SEARCH or OTHER.',
  agent_traffic.source_channel AS source_channel
    WITH SYNONYMS ('channel', 'collection method')
    COMMENT = 'Where the agent was observed: ''cdn'' (edge logs) or ''client'' (JS tracker). Each agent is counted on exactly one channel, so this is a diagnostic, not a slice to sum over.'
)

METRICS (
  agent_traffic.total_agent_hits AS SUM(agent_traffic.hits)
    WITH SYNONYMS ('agent hits', 'crawls', 'bot requests', 'crawler traffic')
    COMMENT = 'Total agent requests.',
  agent_traffic.distinct_agents AS COUNT(DISTINCT agent_traffic.agent_name)
    WITH SYNONYMS ('number of agents', 'how many bots')
    COMMENT = 'Number of distinct agents.',
  agent_traffic.distinct_pages_crawled AS COUNT(DISTINCT agent_traffic.crawled_page)
    WITH SYNONYMS ('pages crawled', 'how many pages')
    COMMENT = 'Number of distinct pages touched by agents.',
  agent_traffic.distinct_operators AS COUNT(DISTINCT agent_traffic.crawling_operator)
    WITH SYNONYMS ('number of operators', 'how many companies')
    COMMENT = 'Number of distinct operators whose agents were seen.',
  agent_traffic.ai_hits AS SUM(CASE WHEN agent_traffic.purpose_group = 'AI' THEN agent_traffic.hits ELSE 0 END)
    WITH SYNONYMS ('ai crawls', 'ai agent hits')
    COMMENT = 'Agent requests from AI-purpose agents only, excluding classic search indexing.',
  agent_traffic.training_hits AS SUM(CASE WHEN agent_traffic.agent_purpose = 'AI_TRAINING' THEN agent_traffic.hits ELSE 0 END)
    WITH SYNONYMS ('training crawls', 'scraping for training')
    COMMENT = 'Agent requests whose purpose is model training.',

  human_traffic.total_human_pageviews AS SUM(human_traffic.human_pageviews)
    WITH SYNONYMS ('human pageviews', 'visits', 'traffic', 'people')
    COMMENT = 'Total human page views.',

  referrals.total_referred_pageviews AS SUM(referrals.referred_pageviews)
    WITH SYNONYMS ('ai referrals', 'referred visits', 'traffic from chatgpt')
    COMMENT = 'Human page views arriving from an AI product.',
  referrals.total_referred_sessions AS SUM(referrals.referred_sessions)
    WITH SYNONYMS ('referred sessions', 'referred visitors')
    COMMENT = 'Sessions behind the referred page views. Accurate for a single day; a multi-day total slightly over-counts sessions spanning midnight.',

  {# Derived metrics span two facts, so they take no table prefix: that scopes them to
     the view rather than to one logical table. #}
  crawl_to_referral_ratio AS agent_traffic.total_agent_hits / NULLIF(referrals.total_referred_sessions, 0)
    WITH SYNONYMS ('take vs give', 'crawl to referral ratio')
    COMMENT = 'Agent requests per referred session. High means the operator crawls far more than it sends back. Undefined (NULL) when there are no referred sessions -- report that as "no referrals recorded", not as zero.',
  agent_share_of_traffic AS agent_traffic.total_agent_hits / NULLIF(agent_traffic.total_agent_hits + human_traffic.total_human_pageviews, 0)
    WITH SYNONYMS ('bot share', 'share of traffic that is agents')
    COMMENT = 'Agent requests as a fraction of all recorded traffic.'
)

COMMENT = 'AI agent traffic, human pageviews and AI referrals at daily grain. The page_summary and operator_summary tables are pre-computed 7/30/90-day rollups of this same data, so any question they answer can be answered here over an arbitrary date range.'

AI_SQL_GENERATION 'Agent traffic and human pageviews come from different collection channels and are not directly comparable as a like-for-like funnel: agent hits count every request (CDN or tracker), human pageviews count tracker page views only. When comparing the two, say so. When reporting referral metrics for an operator, check has_referral_sources -- if it is false, zero referrals means the operator has no referral sources configured, not that it sends no traffic. Never sum referred_sessions across more than one day without noting that sessions spanning midnight are counted twice. source_channel is a diagnostic: each agent appears on exactly one channel, so do not present it as a traffic split.'
