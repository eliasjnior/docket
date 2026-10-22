import DocketCore
import Foundation

/// Core values rendered as the JSON GitHub's GraphQL API returns for Docket's queries.
enum GitHubJSON {
    static func date(_ date: Date?) -> Any {
        guard let date else { return NSNull() }
        return ISO8601DateFormatter().string(from: date)
    }

    static func optional(_ value: Any?) -> Any { value ?? NSNull() }

    static func actor(_ actor: Actor?) -> Any {
        guard let actor else { return NSNull() }
        return ["__typename": actor.isBot ? "Bot" : "User", "login": actor.login]
    }

    static func reviewer(_ reviewer: Reviewer?) -> Any {
        switch reviewer {
        case .user(let login): ["__typename": "User", "login": login]
        case .team(let organization, let slug):
            ["__typename": "Team", "slug": slug, "organization": ["login": organization]]
        case nil: NSNull()
        }
    }

    static func summary(_ pullRequest: PullRequest) -> [String: Any] {
        [
            "id": pullRequest.id, "number": pullRequest.number, "title": pullRequest.title,
            "url": pullRequest.url.absoluteString, "state": pullRequest.state.rawValue, "isDraft": pullRequest.isDraft,
            "createdAt": date(pullRequest.createdAt), "updatedAt": date(pullRequest.updatedAt),
            "author": actor(pullRequest.author),
            "repository": ["nameWithOwner": pullRequest.repository, "isArchived": pullRequest.isArchived],
            "mergeable": pullRequest.mergeable.rawValue,
            "reviewDecision": optional(pullRequest.reviewDecision?.rawValue),
            "commits": [
                "nodes": [
                    [
                        "commit": [
                            "oid": optional(pullRequest.headOID),
                            "committedDate": date(pullRequest.headCommit?.at),
                            "author": optional(
                                pullRequest.headCommit.map { commit in
                                    [
                                        "name": commit.isBot ? "bot[bot]" : "Someone",
                                        "user": optional(commit.login.map { ["login": $0] }),
                                    ] as [String: Any]
                                }),
                            "statusCheckRollup": optional(pullRequest.checks.map { ["state": $0.rawValue] }),
                        ]
                    ]
                ]
            ],
            "body": pullRequest.issueLinks.map { "See \($0.absoluteString)" }.joined(separator: "\n"),
            "headRefName": optional(pullRequest.headRefName),
            "labels": ["nodes": pullRequest.labels.map { ["name": $0.name, "color": $0.color] }],
            "timelineItems": [
                "nodes": pullRequest.lastForcePush.map { push in
                    [["createdAt": date(push.at), "actor": actor(Actor(login: push.login, isBot: push.isBot))]]
                } ?? []
            ],
            "reviewRequests": ["nodes": pullRequest.reviewRequests.map { ["requestedReviewer": reviewer($0)] }],
            "latestOpinionatedReviews": [
                "nodes": pullRequest.latestReviews.map { ["author": ["login": $0.login], "state": $0.state.rawValue] }
            ],
        ]
    }

    static func detail(_ detail: PullRequestDetail) -> [String: Any] {
        [
            "id": detail.id,
            "reviews": [
                "nodes": detail.reviews.map { review in
                    [
                        "id": review.id, "state": review.state.rawValue, "body": review.bodyIsEmpty ? "" : "text",
                        "submittedAt": date(review.submittedAt), "author": actor(review.author),
                    ]
                }
            ],
            "comments": [
                "nodes": detail.comments.map { comment in
                    [
                        "id": comment.id, "url": comment.url.absoluteString, "createdAt": date(comment.createdAt),
                        "author": actor(comment.author),
                    ]
                }
            ],
            "reviewThreads": [
                "nodes": detail.threads.map { thread in
                    [
                        "id": thread.id,
                        "comments": [
                            "nodes": thread.comments.map { comment in
                                [
                                    "id": comment.id, "url": comment.url.absoluteString,
                                    "createdAt": date(comment.createdAt), "author": actor(comment.author),
                                    "pullRequestReview": optional(comment.reviewID.map { ["id": $0] }),
                                ]
                            }
                        ],
                    ]
                }
            ],
            "timelineItems": [
                "nodes": detail.requestEvents.map { event in
                    [
                        "id": event.id, "createdAt": date(event.createdAt), "actor": actor(event.actor),
                        "requestedReviewer": reviewer(event.reviewer),
                    ]
                }
            ],
        ]
    }
}
