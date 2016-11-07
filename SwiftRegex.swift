//
//  SwiftRegex.swift
//  SwiftRegex
//
//  Created by John Holdsworth on 26/06/2014.
//  Copyright (c) 2014 John Holdsworth.
//
//  $Id: //depot/SwiftRegex/SwiftRegex.swift#46 $
//
//  This code is in the public domain from:
//  https://github.com/johnno1962/SwiftRegex
//

import Foundation

private var swiftRegexCache = Dictionary<String,NSRegularExpression>()
public let regexNoGroup = "__nil__"

open class SwiftRegex: NSObject {

    let target: NSString
    let regex: NSRegularExpression
    var regexFile: RegexFile?

    init( target:NSString, pattern:String, options:NSRegularExpression.Options = .dotMatchesLineSeparators ) {
        self.target = target
        if let regex = swiftRegexCache[pattern] {
            self.regex = regex
        } else {
            do {
                let regex = try NSRegularExpression( pattern: pattern, options:options)
                swiftRegexCache[pattern] = regex
                self.regex = regex
            } catch let error as NSError {
                SwiftRegex.failure("Error in pattern: \(pattern) - \(error.localizedDescription)")
                self.regex = NSRegularExpression()
            }
        }
        super.init()
    }

    class func failure( _ message: String ) {
        NSLog( "*** SwiftRegex: \(message)"["%"]["%%"] )
        //assert(false,"SwiftRegex: failed")
    }

    open class func loadFile( _ path: String, bleat: Bool = true ) -> NSMutableString! {
        do {
            let string = try NSMutableString( contentsOfFile: path, encoding: String.Encoding.utf8.rawValue )
            return string
        } catch let error as NSError {
            if bleat {
                failure( "Could not load file: \(path), \(error.localizedDescription)" )
            }
        }
        return nil
    }

    open class func saveFile( _ path: String, newContents: NSString, force: Bool = false ) -> Bool {
        let current = force ? nil : loadFile( path, bleat: false )

        if current == nil || current != newContents {
            do {
                try newContents.write( toFile: path, atomically: true, encoding: String.Encoding.utf8.rawValue)
                return true
            } catch let error as NSError {
                failure( "Could not write to file: \(path), \(error.localizedDescription)" )
            }
        }

        return false
    }

    open class func patchFile( _ path: String, replace pattern: String, with template: String ) -> Bool {
        let patched = loadFile( path )
        (patched?[pattern])! ~= template
        return saveFile( path, newContents: patched! )
    }
    
    final var targetRange: NSRange {
        return NSRange(location: 0,length: target.length)
    }

    final func substring( _ range: NSRange ) -> String! {
        if ( range.location != NSNotFound ) {
            return target.substring(with: range)
        } else {
            return nil
        }
    }

    open func doesMatch( _ options: NSRegularExpression.MatchingOptions? = nil ) -> Bool {
        return range(options).location != NSNotFound
    }

    open func range( _ options: NSRegularExpression.MatchingOptions? = nil ) -> NSRange {
        return regex.rangeOfFirstMatch( in: target as String, options: options ?? NSRegularExpression.MatchingOptions(rawValue: 0), range: targetRange )
    }

    open func match( _ options: NSRegularExpression.MatchingOptions? = nil ) -> String! {
        return substring( range( options ) )
    }

    open func groups( _ options: NSRegularExpression.MatchingOptions? = nil ) -> [String]! {
        return groupsForMatch( regex.firstMatch(in: target as String, options: options ?? NSRegularExpression.MatchingOptions(rawValue: 0), range: targetRange) )
    }

    func groupsForMatch( _ match: NSTextCheckingResult! ) -> [String]! {
        if match != nil {
            var groups = [String]()
            for groupno in 0...regex.numberOfCaptureGroups {
                if let group = substring( match.rangeAt(groupno) ) as String! {
                    groups.append( group )
                } else {
                    groups.append( regexNoGroup ) // avoids bridging problems
                }
            }
            return groups
        } else {
            return nil
        }
    }

    open subscript( groupno: Int ) -> String! {
        get {
            if let groups = groups() {
                let group = groups[groupno]
                return group != regexNoGroup ? group : nil
            } else {
                return nil
            }
        }
        set( newValue ) {
            if let mutableTarget = target as? NSMutableString {
                for match in Array(matchResults().reversed()) {
                    let replacement = regex.replacementString( for: match,
                        in: target as String, offset: 0, template: newValue )
                    mutableTarget.replaceCharacters( in: match.rangeAt(groupno), with: replacement )
                }
            } else {
                SwiftRegex.failure("Group modify on non-mutable")
            }
        }
    }

    open subscript( template: String ) -> String {
        get {
            return replaceWith( template ) as String
        }
    }

    func matchResults( _ options: NSRegularExpression.MatchingOptions? = nil ) -> [NSTextCheckingResult] {
        return regex.matches( in: target as String, options: options ?? NSRegularExpression.MatchingOptions(rawValue: 0), range: targetRange ) as [NSTextCheckingResult]
    }
    
    open func ranges( _ options: NSRegularExpression.MatchingOptions? = nil ) -> [NSRange] {
        return matchResults( options ).map { $0.range }
    }

    open func matches( _ options: NSRegularExpression.MatchingOptions? = nil ) -> [String] {
        return matchResults( options ).map { self.substring($0.range) }
    }
    
    open func allGroups( _ options: NSRegularExpression.MatchingOptions? = nil ) -> [[String]] {
        return matchResults( options ).map { self.groupsForMatch($0) }
    }

    open func dictionary( _ options: NSRegularExpression.MatchingOptions? = nil ) -> Dictionary<String,String> {
        var out = Dictionary<String,String>()
        for match in matchResults(options) {
            out[substring(match.rangeAt(1))] =
                substring(match.rangeAt(2))
        }
        return out
    }

    func substituteMatches( _ substitution: (NSTextCheckingResult, UnsafeMutablePointer<ObjCBool>) -> String ) -> Bool {
        let out = NSMutableString()
        var pos = 0

        regex.enumerateMatches( in: target as String, options: NSRegularExpression.MatchingOptions(rawValue: 0), range: targetRange ) {
            (match: NSTextCheckingResult?, flags: NSRegularExpression.MatchingFlags, stop: UnsafeMutablePointer<ObjCBool>) in

            let matchRange = match!.range
            out.append( self.substring( NSRange(location:pos, length:matchRange.location-pos) ) )
            out.append( substitution(match!, stop) )
            pos = matchRange.location + matchRange.length
        }

        out.append( substring( NSRange(location:pos, length:targetRange.length-pos) ) )

        if let mutableTarget = target as? NSMutableString {
            if out != target {
                mutableTarget.setString(out as String)
                return true
            }
        } else {
            SwiftRegex.failure("Modify on non-mutable")
        }
        return false

    }

    func replaceWith( _ template: String, options: NSRegularExpression.MatchingOptions? = nil ) -> NSMutableString {
        let mutable = /*target as? NSMutableString ??*/ RegexMutable( target )
        regex.replaceMatches( in: mutable, options: options ?? NSRegularExpression.MatchingOptions(rawValue: 0), range: targetRange, withTemplate: template )
        return mutable
    }

/* removed Beta6
    public func __conversion() -> Bool {
        return doesMatch()
    }

    public func __conversion() -> NSRange {
        return range()
    }

    public func __conversion() -> String {
        return match()
    }

    public func __conversion() -> [String] {
        return matches()
    }

    public func __conversion() -> [[String]] {
        return allGroups()
    }

    public func __conversion() -> [String:String] {
        return dictionary()
    }
*/
    open var boolValue: Bool {
        return doesMatch()
    }
}

extension NSString {
    public subscript( pattern: String, options: NSRegularExpression.Options ) -> SwiftRegex {
        return SwiftRegex( target: self, pattern: pattern, options: options )
    }
}

extension String {
    public subscript( pattern: String, options: NSRegularExpression.Options ) -> SwiftRegex {
        return SwiftRegex( target: self as NSString, pattern: pattern, options: options )
    }
}

extension NSString {
    public subscript( pattern: String ) -> SwiftRegex {
        return SwiftRegex( target: self, pattern: pattern )
    }
}

extension String {
    public subscript( pattern: String ) -> SwiftRegex {
        return SwiftRegex( target: self as NSString, pattern: pattern )
    }
}

public func RegexMutable( _ string: NSString ) -> NSMutableString {
    return NSMutableString( string: string )
}

//// for switch
//public var lastRegexMatchGroups: [String!]!
//
//public func ~= ( left: String, right: String ) -> Bool {
//    if let groups = SwiftRegex( target: right, pattern: left ).groups() {
//        lastRegexMatchGroups = groups.map { $0 != regexNoGroup ? $0 : nil }
//        return true
//    }
//    return false
//}

// for replacements
public func ~= ( left: SwiftRegex, right: String ) -> Bool {
    return left.substituteMatches( {
        (match: NSTextCheckingResult, stop: UnsafeMutablePointer<ObjCBool>) in
        return left.regex.replacementString( for: match,
            in: left.target as String, offset: 0, template: right )
    } )
}

public func ~= ( left: SwiftRegex, right: [String] ) -> Bool {
    var matchNumber = 0
    return left.substituteMatches( {
        (match: NSTextCheckingResult, stop: UnsafeMutablePointer<ObjCBool>) in

        matchNumber += 1
        if matchNumber == right.count {
            stop.pointee = true
        }

        return left.regex.replacementString( for: match,
            in: left.target as String, offset: 0, template: right[matchNumber-1] )
    } )
}

public func ~= ( left: SwiftRegex, right: (String) -> String ) -> Bool {
    return left.substituteMatches( {
        (match: NSTextCheckingResult, stop: UnsafeMutablePointer<ObjCBool>) in
        return right( left.substring(match.range) )
    } )
}

public func ~= ( left: SwiftRegex, right: ([String]) -> String ) -> Bool {
    return left.substituteMatches( {
        (match: NSTextCheckingResult, stop: UnsafeMutablePointer<ObjCBool>) in
        return right( left.groupsForMatch(match) )
    } )
}

open class RegexFile {

    let filepath: String
    let contents: NSMutableString!

    public init( _ path: String ) {
        filepath = path
        contents = SwiftRegex.loadFile( path )
    }

    open subscript( pattern: String ) -> SwiftRegex {
        let regex = SwiftRegex( target: contents, pattern: pattern )
        regex.regexFile = self // retains until after substitution
        return regex
    }

    deinit {
        SwiftRegex.saveFile( filepath, newContents: contents )
    }

}
