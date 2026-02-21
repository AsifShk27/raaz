#!/usr/bin/env python3
"""
DuckDuckGo Search CLI - No API key required!

Uses DuckDuckGo HTML endpoint with proper headers to avoid bot detection.

Usage:
    ddg search "your query here"
    ddg search "query" --num 10
    ddg search "query" --format json

Options:
    -n, --num N       Number of results (default: 10)
    -j, --json        Output as JSON
    -h, --help        Show this help
"""

import sys
import argparse
import urllib.request
import urllib.parse
import html
import json
import re
import time


def search_ddg_html(query: str, num_results: int = 10) -> list:
    """Search using DuckDuckGo HTML version"""
    url = f"https://html.duckduckgo.com/html/?q={urllib.parse.quote(query)}"
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.5',
        'Accept-Encoding': 'gzip, deflate',
        'Connection': 'keep-alive',
    }
    
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=20) as response:
            html_content = response.read().decode('utf-8', errors='ignore')
        
        results = []
        
        # Parse DuckDuckGo HTML results
        # Results are in <a> tags with class "result__a" or just result links
        pattern = r'<a[^>]+class="[^"]*result[^"]*"[^>]+href="([^"]*)"[^>]*>([^<]*)</a>'
        matches = re.findall(pattern, html_content, re.IGNORECASE)
        
        # Alternative pattern for plain links
        if not matches:
            pattern = r'<a[^>]+href="(https?://[^"]+)"[^>]*>([^<]{5,200})</a>'
            matches = re.findall(pattern, html_content)
        
        seen = set()
        for href, title in matches:
            # Clean up
            title = html.unescape(title.strip())
            title = re.sub(r'<[^>]+>', '', title)  # Remove any HTML tags
            title = title.strip()
            
            # Filter results
            if (href.startswith('http') and 
                'duckduckgo' not in href and
                len(title) > 5 and
                href not in seen):
                
                # Check for duplicates
                url_domain = href.split('/')[2] if '/' in href else href
                if url_domain not in seen:
                    seen.add(url_domain)
                    seen.add(href)
                    
                    results.append({
                        'title': title,
                        'url': href
                    })
                    
                    if len(results) >= num_results:
                        break
        
        return results
        
    except Exception as e:
        return [{'error': str(e)}]


def search_bing_rss(query: str, num_results: int = 5) -> list:
    """Fallback: Use Bing RSS feed (no API key needed)"""
    # Add language parameter for English results
    url = f"https://www.bing.com/search?q={urllib.parse.quote(query)}&setlang=en-us&cc=US&format=rss"
    
    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }
    
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=20) as response:
            xml_content = response.read().decode('utf-8', errors='ignore')
        
        results = []
        # Parse RSS
        pattern = r'<link>(https?://[^<]+)</link>'
        matches = re.findall(pattern, xml_content)
        
        pattern_title = r'<title>([^<]+)</title>'
        titles = re.findall(pattern_title, xml_content)
        
        # First title is usually the query, skip it
        for i, link in enumerate(matches[:num_results]):
            if link.startswith('http') and 'bing.com' not in link:
                title = titles[i + 1] if i + 1 < len(titles) else "Result"
                results.append({
                    'title': title,
                    'url': link
                })
        
        return results
        
    except Exception as e:
        return [{'error': str(e)}]


def search_searxng(query: str, num_results: int = 10) -> list:
    """Use public SearXNG instance as fallback"""
    # Try a public SearXNG instance
    searx_instances = [
        "https://searx.be",
        "https://searx.org",
        "https://searx.me",
    ]
    
    for instance in searx_instances:
        try:
            url = f"{instance}/search?q={urllib.parse.quote(query)}"
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            }
            
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=15) as response:
                html_content = response.read().decode('utf-8', errors='ignore')
            
            results = []
            pattern = r'<a[^>]+class="url[^"]*"[^>]+href="([^"]*)"[^>]*>([^<]*)</a>'
            matches = re.findall(pattern, html_content)
            
            seen = set()
            for href, title in matches:
                title = html.unescape(title.strip())
                if href.startswith('http') and len(title) > 3 and href not in seen:
                    seen.add(href)
                    results.append({'title': title, 'url': href})
                    if len(results) >= num_results:
                        break
            
            if results:
                return results
                
        except Exception:
            continue
    
    return [{'error': 'All search backends failed'}]


def main():
    parser = argparse.ArgumentParser(
        description='DuckDuckGo Search - No API key required!'
    )
    parser.add_argument('query', nargs='*', help='Search query')
    parser.add_argument('-n', '--num', type=int, default=10, 
                        help='Number of results (default: 10)')
    parser.add_argument('-j', '--json', action='store_true',
                        help='Output as JSON')
    
    args = parser.parse_args()
    
    if not args.query:
        print(__doc__)
        return
    
    query = ' '.join(args.query)
    
    print(f"🔍 Searching for: {query}...", file=sys.stderr)
    
    # Try DuckDuckGo HTML first
    results = search_ddg_html(query, args.num)
    
    # If no results, try Bing RSS
    if not results or ('error' in results[0] and not results[0].get('url')):
        results = search_bing_rss(query, args.num)
    
    # If still no results, try SearXNG
    if not results or ('error' in results[0] and not results[0].get('url')):
        results = search_searxng(query, args.num)
    
    if not results or 'error' in results[0]:
        print("❌ Search failed! Please try again.", file=sys.stderr)
        return
    
    if args.json:
        print(json.dumps(results, indent=2))
    else:
        print(f"\n📋 Search Results:\n")
        print("=" * 80)
        for i, r in enumerate(results, 1):
            if 'error' in r:
                print(f"❌ Error: {r['error']}")
            else:
                print(f"{i}. {r['title']}")
                print(f"   🔗 {r['url']}")
                print()
        print("=" * 80)


if __name__ == '__main__':
    main()
