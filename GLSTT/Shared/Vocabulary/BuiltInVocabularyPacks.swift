import Foundation

struct BuiltInVocabularyPack: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let words: [String]
}

enum BuiltInVocabularyLibrary {
    static let packs: [BuiltInVocabularyPack] = [
        pack(
            id: "texting",
            name: "Texting",
            detail: "Shortforms, slang, and casual phrases.",
            terms: """
            idk, imo, imho, irl, tbh, btw, brb, bbl, ttyl, omg, omw, rn, ngl, fr, frfr, smh, fwiw, afaik, ikr, iirc, tl dr, dm, pm, ping, screenshot, screenshots, meme, memes, emoji, emojis, gif, gifs, subreddit, reddit, discord, facetime, iMessage, AirDrop, wifi, hotspot, selfie, selfies, photodump, doomscroll, doomscrolling, scrollback, livestream, livestreaming, clickbait, ghosted, ghosting, soft launch, hard launch, vibe check, lowkey, highkey, no worries, sounds good, makes sense, gotcha, lemme, gonna, wanna, kinda, outta, yup, nope, pls, plz, thx, tysm, appreciate it, goodnight, good morning, good afternoon, be there soon, running late, send location, on my way, talk later, call me, text me, missed you, miss you, love you, see you soon, sounds great, let me know, check this out, heads up, all good, my bad, no problem, for sure, fair enough, works for me
            """
        ),
        pack(
            id: "swift",
            name: "Swift",
            detail: "Language keywords and concurrency terms.",
            terms: """
            Swift, Codable, Decodable, Encodable, Sendable, async, await, throws, rethrows, actor, actors, MainActor, nonisolated, isolated, Task, task group, TaskGroup, AsyncSequence, AsyncStream, continuation, continuations, Observation, observable, Observable, binding, bindings, property wrapper, property wrappers, generic, generics, protocol, protocols, conformance, conformances, extension, extensions, mutating, associatedtype, opaque type, existential, result builder, result builders, ViewBuilder, defer, guard, enum, enums, struct, structs, class, classes, optional, optionals, nil coalescing, key path, key paths, closure, closures, escaping, autoclosure, inout, fileprivate, public, internal, private, package, availability, macro, macros, hashable, identifiable, equatable, CaseIterable, RawRepresentable, typealias, initializer, initializers, deinitializer, deinit, namespace, namespaces, URLSession, Foundation, AttributedString, observation tracking, strict concurrency, data race, Sendable conformance, if let, guard let, switch case, associated value, raw value, enum case, JSONDecoder, JSONEncoder, synthesized conformance
            """
        ),
        pack(
            id: "swiftui",
            name: "SwiftUI",
            detail: "Views, layout, observation, and app structure.",
            terms: """
            SwiftUI, View, scene, scenes, NavigationStack, NavigationSplitView, TabView, List, LazyVStack, LazyHStack, ScrollView, ScrollViewReader, ForEach, section, sections, toolbar, toolbar item, toolbar items, sheet, sheets, popover, alert, confirmation dialog, full screen cover, matched geometry effect, GeometryReader, preference key, preference keys, safe area, safe area inset, content unavailable view, glass effect, glass prominent, liquid glass, material, thin material, ultra thin material, environment, environment value, environment values, Environment, bindable, Bindable, state, State, binding, Binding, observable, Observable, namespace, Namespace, focus state, FocusState, animation, transition, transitions, content transition, symbol effect, phase animator, keyframe animator, task modifier, refreshable, searchable, commands, menu bar extra, window group, settings scene, container relative frame, view that fits, grid, grids, alignment guide, layout protocol, custom layout, disclosure group, toggle style, button style, label style, control size, navigation destination, inspector, presentation detents, share link, image renderer, canvas, timeline view, scene storage, app storage, onChange, redacted, content margins, scroll position, text editor, text field axis, navigation path, view modifier, z stack, overlay, background
            """
        ),
        pack(
            id: "uikit",
            name: "UIKit",
            detail: "Controllers, views, and iOS application APIs.",
            terms: """
            UIKit, UIView, UIViewController, UIViewRepresentable, UIViewControllerRepresentable, UIWindow, UIWindowScene, UIApplication, app delegate, scene delegate, Auto Layout, layout constraints, NSLayoutConstraint, UIStackView, UICollectionView, UICollectionViewCell, UICollectionViewCompositionalLayout, UICollectionReusableView, UITableView, UITableViewCell, diffable data source, NSDiffableDataSourceSnapshot, cell registration, list content configuration, UIListContentConfiguration, UIHostingController, UIHostingConfiguration, UINavigationController, UITabBarController, UISplitViewController, UISheetPresentationController, UIContextMenuInteraction, UIMenu, UIAction, UIBarButtonItem, UIToolbar, UITextField, UITextView, UITextViewDelegate, UITextFieldDelegate, UIResponder, first responder, responder chain, input accessory view, keyboard notification, UIKeyboardLayoutGuide, gesture recognizer, UIGestureRecognizer, tap gesture recognizer, long press recognizer, pan gesture, pinch gesture, swipe actions, UIRefreshControl, NSLayoutGuide, safe area layout guide, trait collection, UITraitCollection, dark mode, dynamic type, preferred content size category, accessibility identifier, VoiceOver, UIAccessibility, haptic feedback, UIImpactFeedbackGenerator, UINotificationFeedbackGenerator, UICollectionLayoutListConfiguration, compositional section, reuse identifier, snapshot apply, animating differences, NSAttributedString, SF Symbols, symbol configuration, modal presentation, push navigation, dismiss animated, target action, selector, state restoration, deep link, URLContexts
            """
        ),
        pack(
            id: "appkit",
            name: "AppKit",
            detail: "macOS windows, menus, accessibility, and responder APIs.",
            terms: """
            AppKit, NSApplication, NSApp, NSWindow, NSPanel, NSView, NSViewController, NSHostingView, NSHostingController, NSWindowController, NSMenu, NSMenuItem, menu bar extra, status item, NSStatusItem, NSStatusBar, responder chain, first responder, NSResponder, NSWorkspace, NSRunningApplication, activation policy, accessory app, LSUIElement, NSAlert, NSSavePanel, NSOpenPanel, NSTextView, NSTextField, NSScrollView, NSCollectionView, NSTableView, NSOutlineView, NSToolbar, toolbar item, NSTrackingArea, mouse moved, key down, flags changed, NSEvent, event monitor, local monitor, global monitor, NSAccessibility, accessibility element, AXUIElement, AXFocusedUIElement, AXValue, NSColor, NSImage, NSBezierPath, NSVisualEffectView, material, vibrant light, vibrant dark, titlebar, unified toolbar, window placement, screen frame, NSScreen, NSAppearance, command menu, key equivalent, keyboard shortcut, input source, pasteboard, NSPasteboard, drag and drop, NSDraggingInfo, NSDocumentController, NSUserActivity, NSCursor, Dock tile, activation options, NSControl, NSSegmentedControl, NSPopUpButton, disclosure triangle, split view, NSSplitViewController, sidebar, outline disclosure, service menu, NSApplicationDelegate, Apple event, sandbox, entitlement, code signing, notarization
            """
        ),
        pack(
            id: "javascript",
            name: "JavaScript",
            detail: "Core language, browser, and runtime terminology.",
            terms: """
            JavaScript, TypeScript, Node, Node.js, npm, pnpm, yarn, bun, package.json, tsconfig, webpack, Vite, Rollup, Babel, ESLint, Prettier, async function, promise, promises, callback, callbacks, event loop, closure, closures, destructuring, spread operator, rest parameter, optional chaining, nullish coalescing, template literal, object literal, array method, map function, filter function, reduce function, forEach, JSX, TSX, React, Next.js, Svelte, Vue, Angular, Solid, Zustand, Redux, reducer, middleware, fetch API, AbortController, localStorage, sessionStorage, indexedDB, service worker, web worker, DOM, query selector, event listener, pointer events, mutation observer, intersection observer, requestAnimationFrame, setTimeout, CommonJS, ECMAScript module, ESM, import type, export default, tree shaking, source map, stack trace, lint rule, type guard, discriminated union, generic type, inferred type, runtime error, undefined, symbol, bigint, JSON stringify, JSON parse, Express, Fastify, Hono, Prisma, drizzle, Supabase, Firebase, websocket, hydration, memoization, debounce, throttle
            """
        ),
        pack(
            id: "sql",
            name: "SQL",
            detail: "Queries, schema terms, and database operations.",
            terms: """
            SQL, SQLite, PostgreSQL, Postgres, MySQL, MariaDB, query, queries, select statement, insert statement, update statement, delete statement, upsert, join, inner join, left join, right join, full join, cross join, where clause, group by, order by, having clause, limit clause, offset clause, common table expression, CTE, recursive CTE, subquery, correlated subquery, window function, partition by, row number, dense rank, primary key, foreign key, unique index, composite index, covering index, index scan, full table scan, migration, schema, table, tables, column, columns, row, rows, transaction, transactions, commit, rollback, savepoint, constraint, constraints, check constraint, not null, default value, identity column, autoincrement, timestamp, timestamptz, varchar, text column, JSONB, array column, enum type, view, materialized view, trigger, stored procedure, function, aggregate, distinct, union, union all, intersect, except, explain plan, query planner, normalization, denormalization, deadlock, lock wait, isolation level, serializable, read committed, prepared statement, connection pool
            """
        ),
        pack(
            id: "python",
            name: "Python",
            detail: "Python language, tooling, and server terms.",
            terms: """
            Python, pip, pipenv, poetry, pyproject, venv, virtualenv, conda, pytest, unittest, mypy, Ruff, black formatter, FastAPI, Django, Flask, Starlette, asyncio, async def, coroutine, coroutines, generator, generators, list comprehension, dictionary comprehension, dataclass, dataclasses, pydantic, SQLAlchemy, alembic, pandas, NumPy, Jupyter, notebook, type hint, type hints, protocol, protocols, abstract base class, context manager, decorators, decorator, dunder method, magic method, __init__, __repr__, __name__, main guard, f string, walrus operator, iterable, iterator, yield from, exception, exceptions, try except, traceback, GIL, global interpreter lock, multiprocessing, thread pool, event loop, uvicorn, gunicorn, WSGI, ASGI, serializer, deserializer, marshmallow, dependency injection, route handler, model field, keyword argument, positional argument, unpacking, kwargs, args, pathlib, tempfile, subprocess, monkey patch, fixtures, parametrized test, recursion error, package index, wheel, source distribution, pyright, stub file, type alias
            """
        ),
        pack(
            id: "go",
            name: "Go",
            detail: "Go language, concurrency, and server terminology.",
            terms: """
            Go, Golang, goroutine, goroutines, channel, channels, buffered channel, select statement, wait group, WaitGroup, mutex, RWMutex, defer statement, interface type, interfaces, struct tag, receiver, receivers, pointer receiver, value receiver, error interface, errors.Is, errors.As, wrapped error, context package, context deadline, context cancel, context timeout, handler func, http server, middleware, JSON marshaling, JSON unmarshaling, slice, slices, append builtin, map type, make builtin, range loop, rune, runes, byte slice, stringer, iota, constant block, switch case, type assertion, type switch, empty interface, generic type, module path, go.mod, go.sum, package main, go test, benchmark, race detector, go fmt, go vet, staticcheck, build tag, embed directive, sql.DB, database slash sql, transaction, protobuf, gRPC, grpc gateway, Cobra, Viper, interface satisfaction, zero value, nil pointer, panic recover, sync.Map, atomic value, compare and swap, slog logger, chi router, Gin framework, Echo framework, templating, worker pool, fan out, fan in
            """
        ),
        pack(
            id: "kotlin",
            name: "Kotlin",
            detail: "Kotlin and Android development terminology.",
            terms: """
            Kotlin, coroutine, coroutines, suspend function, Flow, StateFlow, SharedFlow, channel, channels, data class, sealed class, sealed interface, companion object, extension function, nullable type, null safety, Elvis operator, safe call, scope function, let function, run function, apply function, also function, inline function, reified type, generic variance, covariance, contravariance, delegation, delegated property, lazy delegate, lateinit, mutable state, Jetpack Compose, recomposition, remember, rememberSaveable, derived state, snapshot flow, ViewModel, lifecycle owner, live data, Room database, DAO, Retrofit, OkHttp, Ktor, serialization, kotlinx serialization, Parcelable, parcelize, intent extra, NavController, navigation compose, Scaffold, Material3, baseline profile, ProGuard, R8, Gradle, build.gradle, settings.gradle, kapt, KSP, DSL marker, suspending lambda, dispatcher, Dispatchers.IO, Dispatchers.Main, structured concurrency, supervisor job, flow collector, combine operator, mapLatest, flatMapLatest, paging, WorkManager, Hilt, dagger, Koin, manifest, AndroidX, activity result, deep link, data store, shared preferences, compose preview, composable, modifier chain
            """
        ),
        pack(
            id: "java",
            name: "Java",
            detail: "Java language, JVM, and backend terminology.",
            terms: """
            Java, JVM, JDK, JRE, javac, Maven, Gradle, Spring, Spring Boot, Hibernate, Jakarta, servlet, servlets, JDBC, JPA, entity manager, dependency injection, bean definition, classpath, module path, package private, synchronized block, volatile field, thread pool, CompletableFuture, virtual thread, records, sealed class, switch expression, stream API, collector, lambda expression, method reference, abstract class, generic type, type erasure, wildcard type, checked exception, unchecked exception, try with resources, AutoCloseable, serialVersionUID, reflection API, proxy class, aspect oriented programming, AOP, REST controller, request mapping, response entity, transactional annotation, optimistic locking, pessimistic locking, connection pool, HikariCP, query method, repository interface, DTO, Jackson, object mapper, deserialization, serialization, Optional, var keyword, text block, pattern matching, garbage collector, heap dump, stack trace, class loader, security manager, JPMS, inheritance, encapsulation, polymorphism, builder pattern, factory pattern, singleton pattern, unit test, JUnit, Mockito, AssertJ, SLF4J, Logback, Micrometer, actuator endpoint, Flyway, Liquibase, servlet filter, interceptor, native image
            """
        ),
    ]

    static func pack(id: String) -> BuiltInVocabularyPack? {
        packs.first(where: { $0.id == id })
    }

    private static func pack(id: String, name: String, detail: String, terms: String) -> BuiltInVocabularyPack {
        BuiltInVocabularyPack(
            id: id,
            name: name,
            detail: detail,
            words: sanitize(terms)
        )
    }

    private static func sanitize(_ terms: String) -> [String] {
        var seen = Set<String>()
        var results: [String] = []

        for raw in terms.components(separatedBy: CharacterSet(charactersIn: ",\n")) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let folded = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(folded).inserted else { continue }
            results.append(trimmed)
        }

        return Array(results.prefix(100))
    }
}
