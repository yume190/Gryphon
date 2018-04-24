internal class GRYSExpressionParser {
	private(set) var contents: String
	private(set) var parenthesesLevel: Int = 0
	private var needsCleaningWhitespace = true
	
	private static let knownComposedKeys = ["interface type="]
	
	init(sExpression contents: String) {
		self.contents = contents
	}
	
	//
	func cleanLeadingWhitespace() {
		if needsCleaningWhitespace {
			needsCleaningWhitespace = false
			
			let whitespacePrefix = contents.prefix(while: { $0 == "\n" || $0 == " " })
			if !whitespacePrefix.isEmpty {
				contents = String(contents.suffix(from: whitespacePrefix.endIndex))
			}
		}
	}
	
	// MARK: - Can read information
	func canReadOpenParentheses() -> Bool {
		cleanLeadingWhitespace()
		return contents.prefix(1) == "("
	}
	
	func canReadCloseParentheses() -> Bool {
		cleanLeadingWhitespace()
		return contents.prefix(1) == ")"
	}
	
	func canReadIdentifierOrString() -> Bool {
		return canReadIdentifier() ||
			canReadDoubleQuotedString() ||
			canReadSingleQuotedString() ||
			canReadStringInBrackets()
	}
	
	func canReadKey() -> Bool {
		cleanLeadingWhitespace()
		
		// Try finding known composed keys before trying for any non-composed keys
		for composedKey in GRYSExpressionParser.knownComposedKeys {
			if contents.hasPrefix(composedKey) {
				return true
			}
		}
		
		// If no known composed keys were found
		// Regex: String start,
		//   many characters but no whitespace, ), (, ", ' or =
		//   then = at the end
		var matchIterator = contents =~ "^[^\\s\\)\\(\"'=]+="
		return matchIterator.next() != nil
	}
	
	func canReadIdentifier() -> Bool {
		cleanLeadingWhitespace()
		// Regex: String start,
		//   many characters but no whitespace, ), (, " or '
		var matchIterator = contents =~ "^[^\\s\\)\\(\"']+"
		return matchIterator.next() != nil
	}
	
	func canReadDoubleQuotedString() -> Bool {
		cleanLeadingWhitespace()
		// Regex: String start,
		//   open ",
		//   many characters but no closing ",
		//   then close "
		var matchIterator = contents =~ "^\"[^\"]+\""
		return matchIterator.next() != nil
	}
	
	func canReadSingleQuotedString() -> Bool {
		cleanLeadingWhitespace()
		// Regex: String start,
		//   open ',
		//   many characters but no closing ',
		//   then close '
		var matchIterator = contents =~ "^'[^']+'"
		return matchIterator.next() != nil
	}
	
	func canReadStringInBrackets() -> Bool {
		cleanLeadingWhitespace()
		// Regex: String start,
		//   open [,
		//   many characters but no closing ],
		//   then close ]
		var matchIterator = contents =~ "^\\[[^\\]]+\\]"
		return matchIterator.next() != nil
	}
	
	func canReadLocation() -> Bool {
		cleanLeadingWhitespace()
		// Regex: String start,
		//   many characters but no :, ( or ) (not greedy so it won't go past this specific location),
		//   then :, a number, :, and another number
		var matchIterator = contents =~ "^([^:\\(\\)]*?):(\\d+):(\\d+)"
		return matchIterator.next() != nil
	}
	
	func canReadDeclarationLocation() -> Bool {
		cleanLeadingWhitespace()
		// Regex: String start,
		//   some character that's not a (,
		//   many characters but no @ or whitespace (not greedy so it won't go past this specific declaration location),
		//   then @
		var matchIterator = contents =~ "^([^\\(][^@\\s]*?)@"
		return matchIterator.next() != nil
	}
	
	// MARK: - Read information
	func readOpenParentheses() {
		guard canReadOpenParentheses() else { fatalError("Parsing error") }
		
		contents.removeFirst()
		parenthesesLevel += 1
		
		log?("-- Open parenthesis: level \(parenthesesLevel)")
	}
	
	func readCloseParentheses() {
		guard canReadCloseParentheses() else { fatalError("Parsing error") }
		defer { needsCleaningWhitespace = true }
		
		contents.removeFirst()
		parenthesesLevel -= 1
		
		log?("-- Close parenthesis: level \(parenthesesLevel)")
	}
	
	func readIdentifierOrString() -> String {
		defer { needsCleaningWhitespace = true }
		
		if canReadOpenParentheses() {
			return ""
		}
		else if canReadDoubleQuotedString() {
			let string = readDoubleQuotedString()
			return "\(string)"
		}
		else if canReadSingleQuotedString() {
			let string = readSingleQuotedString()
			return "\(string)"
		}
		else if canReadStringInBrackets() {
			let string = readStringInBrackets()
			return "\(string)"
		}
		else {
			return readIdentifier()
		}
	}
	
	func readIdentifier() -> String {
		cleanLeadingWhitespace()
		defer { needsCleaningWhitespace = true }
		
		var result = ""
		
		var parenthesesLevel = 0
		loop: for character in contents {
			switch character {
			case "(":
				parenthesesLevel += 1
				result.append(character)
			case ")":
				parenthesesLevel -= 1
				if parenthesesLevel < 0 {
					break loop
				}
				else {
					result.append(character)
				}
			case " ", "\n": break loop
			default:
				result.append(character)
			}
		}
		
		log?("-- Read identifier: \"\(result)\"")
		contents.removeFirst(result.count)
		return result
	}
	
	func readKey() -> String {
		cleanLeadingWhitespace()
		defer { needsCleaningWhitespace = true }
		
		// Try finding known composed keys before trying for any non-composed keys
		for composedKey in GRYSExpressionParser.knownComposedKeys {
			if contents.hasPrefix(composedKey) {
				log?("-- Read composed key: \"\(composedKey)\"")
				contents.removeFirst(composedKey.count)
				let result = composedKey.dropLast()
				return String(result)
			}
		}
		
		// If no known composed keys were found
		// Regex: String start,
		//   many characters but no whitespace, ), (, ", ' or =
		//   then = at the end
		var matchIterator = contents =~ "^[^\\s\\)\\(\"'=]+="
		guard let match = matchIterator.next() else { fatalError("Parsing error") }
		let matchedString = match.matchedString
		log?("-- Read key: \"\(matchedString)\"")
		contents.removeFirst(matchedString.count)
		let result = matchedString.dropLast()
		return String(result)
	}
	
	func readLocation() -> String {
		cleanLeadingWhitespace()
		defer { needsCleaningWhitespace = true }
		
		// Regex: String start,
		//   many characters but no : (not greedy so it won't go past this specific location),
		//   then :, a number, :, and another number
		var matchIterator = contents =~ "^([^:]*?):(\\d+):(\\d+)"
		guard let match = matchIterator.next() else { fatalError("Parsing error") }
		let matchedString = match.matchedString
		log?("-- Read location: \"\(matchedString)\"")
		contents.removeFirst(matchedString.count)
		return matchedString
	}
	
	func readDeclarationLocation() -> String {
		cleanLeadingWhitespace()
		defer { needsCleaningWhitespace = true }
		
		// Regex: String start,
		//   many characters but no @ or whitespace (not greedy so it won't go past this specific declaration location),
		//   then @
		var matchIterator = contents =~ "^([^@\\s]*?)@"
		guard let match = matchIterator.next() else { fatalError("Parsing error") }
		let matchedString = match.matchedString
		log?("-- Read declaration location: \"\(matchedString)\"")
		contents.removeFirst(matchedString.count)
		
		let location = readLocation()
		
		return matchedString + location
	}
	
	func readDoubleQuotedString() -> String {
		cleanLeadingWhitespace()
		defer { needsCleaningWhitespace = true }
		
		// Regex: String start,
		//   open ",
		//   many characters but no closing ",
		//   then close "
		var matchIterator = contents =~ "^\"[^\"]+\""
		guard let match = matchIterator.next() else { fatalError("Parsing error") }
		let matchedString = match.matchedString
		log?("-- String: \"\(matchedString)\"")
		contents.removeFirst(matchedString.count)
		let result = matchedString.dropFirst().dropLast()
		return String(result)
	}
	
	func readSingleQuotedString() -> String {
		cleanLeadingWhitespace()
		defer { needsCleaningWhitespace = true }
		
		// Regex: String start,
		//   open ',
		//   many characters but no closing ',
		//   then close '
		var matchIterator = contents =~ "^'[^']+'"
		guard let match = matchIterator.next() else { fatalError("Parsing error") }
		let matchedString = match.matchedString
		log?("-- String: \"\(matchedString)\"")
		contents.removeFirst(matchedString.count)
		let result = matchedString.dropFirst().dropLast()
		return String(result)
	}
	
	func readStringInBrackets() -> String {
		cleanLeadingWhitespace()
		defer { needsCleaningWhitespace = true }
		
		// Regex: String start,
		//   open [,
		//   many characters but no closing ],
		//   then close ]
		var matchIterator = contents =~ "^\\[[^\\]]+\\]"
		guard let match = matchIterator.next() else { fatalError("Parsing error") }
		let matchedString = match.matchedString
		log?("-- String: \"\(matchedString)\"")
		contents.removeFirst(matchedString.count)
		let result = matchedString.dropFirst().dropLast()
		return String(result)
	}
}
