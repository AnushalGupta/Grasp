import Foundation

struct MediaGrabberScript {
    static let scriptSource = """
    (function() {
        if (window.__graspMediaGrabberInjected) return;
        window.__graspMediaGrabberInjected = true;

        console.log("[Grasp Media Grabber] Injected successfully.");

        // Utility to send media details back to native Swift
        function reportMedia(url, title, type, sourceElement = "unknown") {
            if (!url) return;
            
            // Resolve relative URLs to absolute
            try {
                const absoluteUrl = new URL(url, document.baseURI).href;
                
                // Avoid duplicates within short timeframe
                const cacheKey = absoluteUrl + "_" + type;
                if (window.__graspReportedCache && window.__graspReportedCache.has(cacheKey)) {
                    return;
                }
                if (!window.__graspReportedCache) {
                    window.__graspReportedCache = new Set();
                }
                window.__graspReportedCache.add(cacheKey);
                setTimeout(() => window.__graspReportedCache.delete(cacheKey), 3000);

                const payload = {
                    url: absoluteUrl,
                    title: title || document.title || "Grabbed Media",
                    type: type || "video/mp4",
                    source: sourceElement
                };

                console.log("[Grasp Media Grabber] Detected media:", payload);
                window.webkit.messageHandlers.mediaGrabber.postMessage(payload);
            } catch (e) {
                console.error("[Grasp Media Grabber] Error resolving URL:", e);
            }
        }

        // Helper to infer MIME type from file extension
        function guessMimeType(url) {
            const ext = url.split(/[?#]/)[0].split('.').pop().toLowerCase();
            const mimeMap = {
                'mp4': 'video/mp4',
                'm3u8': 'application/x-mpegURL',
                'ts': 'video/MP2T',
                'mp3': 'audio/mpeg',
                'wav': 'audio/wav',
                'ogg': 'audio/ogg',
                'webm': 'video/webm',
                'mkv': 'video/x-matroska',
                'mov': 'video/quicktime',
                'flv': 'video/x-flv',
                'aac': 'audio/aac'
            };
            return mimeMap[ext] || 'video/mp4';
        }

        // 1. Hook HTMLMediaElement prototype
        try {
            const originalPlay = HTMLMediaElement.prototype.play;
            HTMLMediaElement.prototype.play = function() {
                const src = this.currentSrc || this.src;
                if (src) {
                    reportMedia(src, document.title, guessMimeType(src), this.tagName.toLowerCase());
                }
                
                // Also setup event listeners
                setupElementListeners(this);
                return originalPlay.apply(this, arguments);
            };

            const originalLoad = HTMLMediaElement.prototype.load;
            HTMLMediaElement.prototype.load = function() {
                const src = this.src;
                if (src) {
                    reportMedia(src, document.title, guessMimeType(src), this.tagName.toLowerCase());
                }
                return originalLoad.apply(this, arguments);
            };
        } catch(e) {
            console.error("[Grasp Media Grabber] Error overriding media prototype:", e);
        }

        // Setup individual element event handlers
        function setupElementListeners(el) {
            if (el.__graspListenersAttached) return;
            el.__graspListenersAttached = true;

            const handleSourceChange = () => {
                const src = el.currentSrc || el.src;
                if (src) {
                    reportMedia(src, document.title, guessMimeType(src), el.tagName.toLowerCase());
                }
            };

            el.addEventListener('play', handleSourceChange);
            el.addEventListener('playing', handleSourceChange);
            el.addEventListener('loadstart', handleSourceChange);
            el.addEventListener('loadedmetadata', handleSourceChange);

            // Watch for changes in child <source> elements
            const observer = new MutationObserver((mutations) => {
                mutations.forEach((mutation) => {
                    if (mutation.type === 'childList') {
                        const sources = el.getElementsByTagName('source');
                        for (let i = 0; i < sources.length; i++) {
                            const s = sources[i];
                            if (s.src) {
                                reportMedia(s.src, document.title, s.type || guessMimeType(s.src), "source_tag");
                            }
                        }
                    }
                });
            });
            observer.observe(el, { childList: true });
        }

        // Scan existing media elements on the page
        function scanMediaElements() {
            const videos = document.getElementsByTagName('video');
            for (let i = 0; i < videos.length; i++) {
                setupElementListeners(videos[i]);
                const src = videos[i].currentSrc || videos[i].src;
                if (src) {
                    reportMedia(src, document.title, guessMimeType(src), "video");
                }
            }

            const audios = document.getElementsByTagName('audio');
            for (let i = 0; i < audios.length; i++) {
                setupElementListeners(audios[i]);
                const src = audios[i].currentSrc || audios[i].src;
                if (src) {
                    reportMedia(src, document.title, guessMimeType(src), "audio");
                }
            }

            // Also check standard anchor tags with downloadable media extensions
            const anchors = document.getElementsByTagName('a');
            const mediaRegex = /\\.(mp4|m3u8|ts|mp3|wav|webm|mkv|mov|flv|aac)([?#].*)?$/i;
            for (let i = 0; i < anchors.length; i++) {
                const href = anchors[i].href;
                if (href && mediaRegex.test(href)) {
                    reportMedia(href, anchors[i].innerText || document.title, guessMimeType(href), "anchor");
                }
            }
        }

        // Run scanning initially and periodically
        scanMediaElements();
        setInterval(scanMediaElements, 3000);

        // 2. Hook Fetch API for media stream urls
        try {
            const originalFetch = window.fetch;
            window.fetch = function(input, init) {
                let url = "";
                if (typeof input === 'string') {
                    url = input;
                } else if (input instanceof Request) {
                    url = input.url;
                } else if (input && typeof input.toString === 'function') {
                    url = input.toString();
                }

                const mediaRegex = /\\.(mp4|m3u8|ts|mp3|wav|webm|mkv|mov|flv|aac)([?#].*)?$/i;
                if (url && mediaRegex.test(url)) {
                    reportMedia(url, "Fetch Stream", guessMimeType(url), "fetch");
                }
                return originalFetch.apply(this, arguments);
            };
        } catch (e) {
            console.error("[Grasp Media Grabber] Error hooking Fetch API:", e);
        }

        // 3. Hook XMLHttpRequest (XHR) for media chunks/streams
        try {
            const originalOpen = XMLHttpRequest.prototype.open;
            XMLHttpRequest.prototype.open = function(method, url) {
                this.__graspUrl = url;
                return originalOpen.apply(this, arguments);
            };

            const originalSend = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.send = function() {
                const url = this.__graspUrl;
                const mediaRegex = /\\.(mp4|m3u8|ts|mp3|wav|webm|mkv|mov|flv|aac)([?#].*)?$/i;
                if (url && mediaRegex.test(url)) {
                    reportMedia(url, "XHR Stream", guessMimeType(url), "xhr");
                }
                return originalSend.apply(this, arguments);
            };
        } catch (e) {
            console.error("[Grasp Media Grabber] Error hooking XHR:", e);
        }

        // 4. Handle contextmenu & long-press on media elements
        let touchStartTimeout = null;
        let lastTouchEl = null;

        document.addEventListener('touchstart', function(e) {
            const target = e.target;
            const isMedia = target.tagName === 'VIDEO' || target.tagName === 'AUDIO';
            const isMediaAnchor = target.tagName === 'A' && /\\.(mp4|m3u8|ts|mp3|wav|webm|mkv|mov|flv|aac)([?#].*)?$/i.test(target.href);
            
            if (isMedia || isMediaAnchor) {
                lastTouchEl = target;
                touchStartTimeout = setTimeout(function() {
                    // Trigger long-press context download popup
                    const src = target.currentSrc || target.src || target.href;
                    if (src) {
                        const payload = {
                            url: new URL(src, document.baseURI).href,
                            title: document.title,
                            type: guessMimeType(src),
                            source: target.tagName.toLowerCase(),
                            action: "long_press"
                        };
                        window.webkit.messageHandlers.mediaGrabber.postMessage(payload);
                    }
                }, 750); // 750ms hold
            }
        }, { passive: true });

        document.addEventListener('touchend', function() {
            if (touchStartTimeout) {
                clearTimeout(touchStartTimeout);
                touchStartTimeout = null;
            }
        });

        document.addEventListener('touchmove', function() {
            if (touchStartTimeout) {
                clearTimeout(touchStartTimeout);
                touchStartTimeout = null;
            }
        });

        // Intercept right-click context menu (especially for desktop web mockups/trackpad clicks)
        document.addEventListener('contextmenu', function(e) {
            const target = e.target;
            const isMedia = target.tagName === 'VIDEO' || target.tagName === 'AUDIO';
            const isMediaAnchor = target.tagName === 'A' && /\\.(mp4|m3u8|ts|mp3|wav|webm|mkv|mov|flv|aac)([?#].*)?$/i.test(target.href);
            
            if (isMedia || isMediaAnchor) {
                const src = target.currentSrc || target.src || target.href;
                if (src) {
                    e.preventDefault(); // Prevent standard browser menu
                    const payload = {
                        url: new URL(src, document.baseURI).href,
                        title: document.title,
                        type: guessMimeType(src),
                        source: target.tagName.toLowerCase(),
                        action: "context_menu"
                    };
                    window.webkit.messageHandlers.mediaGrabber.postMessage(payload);
                }
            }
        });

    })();
    """
}
