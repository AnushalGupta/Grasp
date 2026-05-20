import Foundation
import WebKit

class AdBlockerManager: ObservableObject {
    static let shared = AdBlockerManager()
    
    @Published var isCompiling = false
    @Published var compilationProgress: Float = 0.0
    @Published var activeRuleList: WKContentRuleList?
    
    private let listIdentifier = "com.antigravity.grasp.adblocker"
    
    private init() {
        // Try to load already compiled rules at startup
        loadExistingRuleList()
    }
    
    /// Loads a precompiled rule list if available
    func loadExistingRuleList() {
        WKContentRuleListStore.default()?.lookUpContentRuleList(forIdentifier: listIdentifier) { [weak self] (ruleList, error) in
            DispatchQueue.main.async {
                if let ruleList = ruleList {
                    self?.activeRuleList = ruleList
                    print("[AdBlocker] Successfully loaded cached rule list.")
                } else {
                    print("[AdBlocker] No cached rule list found. Compiling default rules...")
                    self?.compileDefaultRules()
                }
            }
        }
    }
    
    /// Compiles fallback rules when no filter files have been downloaded yet
    func compileDefaultRules() {
        let defaultFilters = """
        ! Compact Default Filter List for Grasp
        ||doubleclick.net^
        ||googleads.g.doubleclick.net^
        ||googlesyndication.com^
        ||google-analytics.com^
        ||adservice.google.com^
        ||adnxs.com^
        ||taboola.com^
        ||outbrain.com^
        ||adroll.com^
        ||rubiconproject.com^
        ||pubmatic.com^
        ||openx.net^
        ||popads.net^
        ||adsterra.com^
        ||exoclick.com^
        ||mgid.com^
        ||onclickads.net^
        ##.ad-box
        ##.ad-banner
        ##.sponsor-banner
        ##.adsbygoogle
        ##[class*="sponsor"]
        ##[id*="ad-container"]
        ##.ad-text
        """
        
        compile(filterRulesText: defaultFilters)
    }
    
    /// Compiles rules from an EasyList text file or raw filter rules
    func compile(filterRulesText: String, completion: ((Bool) -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isCompiling = true
                self.compilationProgress = 0.1
            }
            
            let jsonRulesString = self.parseEasyListToSafariJSON(filterRulesText)
            
            DispatchQueue.main.async {
                self.compilationProgress = 0.5
            }
            
            guard let store = WKContentRuleListStore.default() else {
                DispatchQueue.main.async {
                    self.isCompiling = false
                    completion?(false)
                }
                return
            }
            
            store.compileContentRuleList(forIdentifier: self.listIdentifier, encodedContentRuleList: jsonRulesString) { [weak self] (ruleList, error) in
                DispatchQueue.main.async {
                    self?.isCompiling = false
                    self?.compilationProgress = 1.0
                    
                    if let error = error {
                        print("[AdBlocker] Compilation failed: \(error.localizedDescription)")
                        completion?(false)
                    } else if let ruleList = ruleList {
                        self?.activeRuleList = ruleList
                        print("[AdBlocker] Rules successfully compiled and applied.")
                        completion?(true)
                    }
                }
            }
        }
    }
    
    /// Parses raw EasyList/uBlock text filters into Safari Content Blocker JSON
    private func parseEasyListToSafariJSON(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var rules: [[String: Any]] = []
        
        var globalCosmeticSelectors: [String] = []
        var domainSpecificCosmeticRules: [String: [String]] = [:] // domain: [selectors]
        
        print("[AdBlocker] Starting parse of \(lines.count) lines...")
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Skip comments and empty lines
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") {
                continue
            }
            
            // 1. Check if it's a Cosmetic Rule (contains ## or #@#)
            if line.contains("##") {
                let parts = line.components(separatedBy: "##")
                if parts.count == 2 {
                    let domainsString = parts[0].trimmingCharacters(in: .whitespaces)
                    let selector = parts[1].trimmingCharacters(in: .whitespaces)
                    
                    if domainsString.isEmpty {
                        // Global cosmetic rule
                        globalCosmeticSelectors.append(selector)
                    } else {
                        // Domain-specific cosmetic rule
                        let domains = domainsString.components(separatedBy: ",")
                        for domain in domains {
                            let cleanDomain = domain.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "~", with: "")
                            domainSpecificCosmeticRules[cleanDomain, default: []].append(selector)
                        }
                    }
                }
                continue
            }
            
            // 2. Exception Cosmetic Rule (contains #@#)
            if line.contains("#@#") {
                // Safari JSON format doesn't have a simple declarative 'ignore-cosmetic' selector,
                // but we can bypass specific domains if needed. Skipping for simplicity or handling exception rules.
                continue
            }
            
            // 3. Network Block Exception Rule (@@||example.com)
            if line.hasPrefix("@@") {
                let ruleBody = String(line.dropFirst(2))
                if let rule = parseNetworkRule(ruleBody, isException: true) {
                    rules.append(rule)
                }
                continue
            }
            
            // 4. Standard Network Block Rule (||example.com)
            if let rule = parseNetworkRule(line, isException: false) {
                rules.append(rule)
            }
        }
        
        // --- OPTIMIZATION ENGINE: Merge global cosmetic rules into comma-separated groups ---
        // Apple's WKContentRuleListStore compiles much faster when similar rules are grouped.
        // We pack up to 80 selectors into a single selector separated by commas.
        let groupSize = 80
        var groupIndex = 0
        while groupIndex < globalCosmeticSelectors.count {
            let endIndex = min(groupIndex + groupSize, globalCosmeticSelectors.count)
            let chunk = globalCosmeticSelectors[groupIndex..<endIndex]
            let mergedSelector = chunk.joined(separator: ", ")
            
            let cosmeticRule: [String: Any] = [
                "trigger": [
                    "url-filter": ".*"
                ],
                "action": [
                    "type": "css-display-none",
                    "selector": mergedSelector
                ]
            ]
            rules.append(cosmeticRule)
            groupIndex += groupSize
        }
        
        // Merge domain-specific cosmetic rules
        for (domain, selectors) in domainSpecificCosmeticRules {
            var sIndex = 0
            while sIndex < selectors.count {
                let sEnd = min(sIndex + groupSize, selectors.count)
                let chunk = selectors[sIndex..<sEnd]
                let mergedSelector = chunk.joined(separator: ", ")
                
                let rule: [String: Any] = [
                    "trigger": [
                        "url-filter": "^https?://+([^:/]+\\.)?\(escapeRegex(domain))[:/]",
                        "load-type": ["first-party"]
                    ],
                    "action": [
                        "type": "css-display-none",
                        "selector": mergedSelector
                    ]
                ]
                rules.append(rule)
                sIndex += groupSize
            }
        }
        
        // Convert rules to JSON
        do {
            // Keep rules count within Safari limits (max 150,000 but we limit to 40,000 for simulator responsiveness)
            let trimmedRules = Array(rules.prefix(40000))
            let jsonData = try JSONSerialization.data(withJSONObject: trimmedRules, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print("[AdBlocker] Parsed filters successfully. Total compiled rules: \(trimmedRules.count)")
                return jsonString
            }
        } catch {
            print("[AdBlocker] JSON serialization error: \(error)")
        }
        
        return "[]"
    }
    
    /// Parses standard EasyList network rules
    private func parseNetworkRule(_ ruleText: String, isException: Bool) -> [String: Any]? {
        var cleanRule = ruleText
        var options: [String] = []
        
        // Extract options (delimited by $)
        if let dollarIndex = ruleText.firstIndex(of: "$") {
            cleanRule = String(ruleText[..<dollarIndex])
            let optionsString = String(ruleText[dollarIndex...].dropFirst())
            options = optionsString.components(separatedBy: ",")
        }
        
        if cleanRule.isEmpty { return nil }
        
        var urlFilter = ""
        
        if cleanRule.hasPrefix("||") {
            // Domain rule matching host and subdomains
            let domain = String(cleanRule.dropFirst(2)).replacingOccurrences(of: "^", with: "")
            urlFilter = "^https?://+([^:/]+\\.)?\(escapeRegex(domain))[:/]"
        } else if cleanRule.hasPrefix("|") && cleanRule.hasSuffix("|") {
            // Exact URL rule
            let url = String(cleanRule.dropFirst().dropLast())
            urlFilter = "^" + escapeRegex(url) + "$"
        } else {
            // Containment rule (contains wildcards)
            let wildcardEscaped = escapeRegex(cleanRule)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\^", with: "[:/]")
            urlFilter = wildcardEscaped
        }
        
        var trigger: [String: Any] = [
            "url-filter": urlFilter
        ]
        
        // Handle Options
        var resourceTypes: [String] = []
        var loadTypes: [String] = []
        
        for option in options {
            switch option {
            case "script":
                resourceTypes.append("script")
            case "image":
                resourceTypes.append("image")
            case "stylesheet":
                resourceTypes.append("style-sheet")
            case "xmlhttprequest":
                resourceTypes.append("raw")
            case "subdocument":
                resourceTypes.append("document")
            case "third-party":
                loadTypes.append("third-party")
            case "first-party":
                loadTypes.append("first-party")
            default:
                break
            }
        }
        
        if !resourceTypes.isEmpty {
            trigger["resource-type"] = resourceTypes
        }
        if !loadTypes.isEmpty {
            trigger["load-type"] = loadTypes
        }
        
        let action: [String: Any] = [
            "type": isException ? "ignore-previous-rules" : "block"
        ]
        
        return [
            "trigger": trigger,
            "action": action
        ]
    }
    
    /// Escapes special characters for regex inclusion
    private func escapeRegex(_ string: String) -> String {
        var escaped = string
        let specialChars = ["\\", ".", "[", "]", "{", "}", "(", ")", "*", "+", "?", "^", "$", "|"]
        for char in specialChars {
            escaped = escaped.replacingOccurrences(of: char, with: "\\" + char)
        }
        return escaped
    }
    
    /// Removes rule list from store
    func clearAllRules() {
        WKContentRuleListStore.default()?.removeContentRuleList(forIdentifier: listIdentifier) { [weak self] _ in
            DispatchQueue.main.async {
                self?.activeRuleList = nil
                print("[AdBlocker] Cleared all adblocking rules.")
            }
        }
    }
}
