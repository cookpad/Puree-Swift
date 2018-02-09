# Puree

[![Build Status](https://travis-ci.org/cookpad/Puree-Swift.svg?branch=master)](https://travis-ci.org/cookpad/Puree-Swift)
[![Language](https://img.shields.io/badge/language-Swift%204.0.2-orange.svg)](https://swift.org)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage) 
[![CocoaPods Compatible](https://img.shields.io/cocoapods/v/Puree.svg)](http://cocoadocs.org/docsets/Puree)
[![Platform](https://img.shields.io/cocoapods/p/Puree.svg?style=flat)](http://cocoadocs.org/docsets/Puree)
[![License](https://cocoapod-badges.herokuapp.com/l/Puree/badge.svg)](https://github.com/cookpad/Puree-Swift/blob/master/LICENSE)

## Description

Puree is a log aggregator which provides the following features.

- Filtering: Log entries can be processed before being sent. You can add common parameters, do random sampling, ...
- Buffering: Log entries are stored in a buffer until it's time to send them.
- Batching: Multiple log entries are grouped and sent in one request.
- Retrying: Automatically retry to send after some backoff time if a transmission error occurred.

![](./Documentation/overview.png)

Puree helps you unify your logging infrastructure.

Currently in development so the interface might change.

## Installation

### Carthage

```
github "cookpad/Puree-Swift"
```

### CocoaPods

```ruby
use_frameworks!

pod 'Puree', '~> 3.0'
```

## Usage

### Define your own Filter/Output

#### Filter

A `Filter` should convert any objects into `LogEntry`.

```swift
import Foundation
import Puree

struct PVLogFilter: Filter {
    let tagPattern: TagPattern

    init(tagPattern: TagPattern, options: FilterOptions?) {
        self.tagPattern = tagPattern
    }

    func convertToLogs(_ payload: [String: Any]?, tag: String, captured: String?, logger: Logger) -> Set<LogEntry> {
        let currentDate = logger.currentDate

        let userData: Data?
        if let payload = payload {
            userData = try! JSONSerialization.data(withJSONObject: payload)
        } else {
            userData = nil
        }
        let log = LogEntry(tag: tag,
                           date: currentDate,
                           userData: userData)
        return [log]
    }
}
```

#### Output

An `Output` should emit log entries to wherever they need.

The following `ConsoleOutput` will output logs to the standard output.

```swift
class ConsoleOutput: Output {
    let tagPattern: String

    init(logStore: LogStore, tagPattern: String, options: OutputOptions?) {
        self.tagPattern = tagPattern
    }

    func emit(log: Log) {
        if let userData = log.userData {
            let jsonObject = try! JSONSerialization.jsonObject(with: log.userData)
            print(jsonObject)
        }
    }
}
```

##### BufferedOutput

If you use `BufferedOutput` instead of raw `Output`, log entries are buffered and emitted on a routine schedule.

```swift
class LogServerOutput: BufferedOutput {
    override func write(_ chunk: BufferedOutput.Chunk, completion: @escaping (Bool) -> Void) {
        let payload = chunk.logs.flatMap { log in
            if let userData = log.userData {
                return try? JSONSerialization.jsonObject(with: userData, options: [])
            }
            return nil
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: []) {
            let task = URLSession.shared.uploadTask(with: request, from: data)
            task.resume()
        }
    }
}
```

### Make logger and post log

After implementing filters and outputs, you can configure the routing with `Logger.Configuration`.

```swift
import Puree

let configuration = Logger.Configuration(logStore: FileLogStore.default,
                                         filterSettings: [
                                             FilterSetting(PVLogFilter.self,
                                                           tagPattern: TagPattern(string: "pv.**")!),
                                         ],
                                         outputSettings: [
                                             OutputSetting(ConsoleOutput.self,
                                                           tagPattern: TagPattern(string: "activity.**")!),
                                             OutputSetting(ConsoleOutput.self,
                                                           tagPattern: TagPattern(string: "pv.**")!),
                                             OutputSetting(LogServerOutput.self,
                                                           tagPattern: TagPattern(string: "pv.**")!),
                                         ])
let logger = try! Logger(configuration: configuration)
logger.postLog(["page_name": "top", "user_id": 100], tag: "pv.top")
```

Using this configuration, the expected result is as follows:

|tag name              |-> [ Filter Plugin ] |-> [ Output Plugin ] |
|----------------------|---------------------|---------------------|
|pv.recipe.list        |-> [ `PVLogFilter` ] |-> [ `ConsoleOutput` ], [ `LogServerOutput` ]|
|pv.recipe.detail      |-> [ `PVLogFilter` ] |-> [ `ConsoleOutput` ], [ `LogServerOutput` ]|
|activity.recipe.tap   |-> ( no filter )     |-> [ `ConsoleOutput` ] |
|event.special         |-> ( no filter )     |-> ( no output ) |


We recommend suspending loggers while the application is in the background.

```swift
class AppDelegate: UIApplicationDelegate {
    func applicationDidEnterBackground(_ application: UIApplication) {
        logger.suspend()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        logger.resume()
    }
}
```

## Tag system

### Tag

A tag is consisted of multiple term delimited by `.`.
For example `activity.recipe.view`, `pv.recipe_detail`.
You can choose your tags logged freely.

### Pattern

`Filter`, `Output` and `BufferedOutput` plugins are applied to log entries with a matching tag.
You can specify tag pattern for plugin reaction rules.

#### Simple pattern

Pattern `aaa.bbb` matches tag `aaa.bbb`, doesn't match tag `aaa.ccc` (Perfect matching).

#### Wildcard

Pattern `aaa.*` matches tags `aaa.bbb` and `aaa.ccc`, but not `aaa` or `aaa.bbb.ccc` (single term).

Pattern `aaa.**` matches tags `aaa`, `aaa.bbb` and `aaa.bbb.ccc`, but not `xxx.yyy.zzz` (zero or more terms).

## Log Store

In the case an application couldn't send log entries (e.g. network connection unavailable), Puree stores the unsent entries.

By default, Puree stores them in local files in the `Library/Caches` directory.

You can also define your own custom log store backed by any storage (e.g. Core Data, Realm, YapDatabase, etc.).

See the `LogStore` protocol for more details.
