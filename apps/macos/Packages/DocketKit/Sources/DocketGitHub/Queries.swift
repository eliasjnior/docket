import Foundation

/// The GraphQL documents of `docs/02-activity-detection.md` §6.1. Every one reads `rateLimit`.
enum Queries {
    static let rateLimit = "rateLimit { cost remaining limit resetAt }"

    static let viewer = "query { viewer { login } \(rateLimit) }"

    static let search = """
        query($authored: String!, $requested: String!, $commented: String!, $reviewed: String!,
              $authoredAfter: String, $requestedAfter: String, $commentedAfter: String, $reviewedAfter: String,
              $withAuthored: Boolean!, $withRequested: Boolean!, $withCommented: Boolean!, $withReviewed: Boolean!) {
          authored: search(query: $authored, type: ISSUE, first: 50, after: $authoredAfter)
            @include(if: $withAuthored) { ...page }
          requested: search(query: $requested, type: ISSUE, first: 50, after: $requestedAfter)
            @include(if: $withRequested) { ...page }
          commented: search(query: $commented, type: ISSUE, first: 50, after: $commentedAfter)
            @include(if: $withCommented) { ...page }
          reviewed: search(query: $reviewed, type: ISSUE, first: 50, after: $reviewedAfter)
            @include(if: $withReviewed) { ...page }
          \(rateLimit)
        }
        fragment page on SearchResultItemConnection {
          issueCount
          pageInfo { hasNextPage endCursor }
          nodes { ... on PullRequest { id updatedAt } }
        }
        """

    static let actor = "__typename login"
    static let reviewer =
        "requestedReviewer { __typename ... on User { login } ... on Team { slug organization { login } } }"

    static let summary = """
        query($ids: [ID!]!) {
          nodes(ids: $ids) {
            ... on PullRequest {
              id number title url state isDraft createdAt updatedAt body headRefName
              author { \(actor) }
              repository { nameWithOwner isArchived }
              mergeable reviewDecision mergedBy { login }
              labels(first: 10) { nodes { name color } }
              commits(last: 1) {
                nodes { commit { oid committedDate author { name user { login } } statusCheckRollup { state } } }
              }
              timelineItems(last: 1, itemTypes: [HEAD_REF_FORCE_PUSHED_EVENT]) {
                nodes { ... on HeadRefForcePushedEvent { createdAt actor { \(actor) } } }
              }
              reviewRequests(first: 10) { nodes { \(reviewer) } }
              latestOpinionatedReviews(first: 10) { nodes { author { login } state } }
            }
          }
          \(rateLimit)
        }
        """

    static let detail = """
        query($ids: [ID!]!) {
          nodes(ids: $ids) {
            ... on PullRequest {
              id
              reviews(last: 30) { nodes { id state body submittedAt author { \(actor) } } }
              comments(last: 30) { nodes { id url body createdAt author { \(actor) } } }
              reviewThreads(last: 30) {
                nodes {
                  id
                  comments(last: 20) { nodes { id url body createdAt author { \(actor) } pullRequestReview { id } } }
                }
              }
              timelineItems(last: 20, itemTypes: [REVIEW_REQUESTED_EVENT, CLOSED_EVENT]) {
                nodes {
                  __typename
                  ... on ReviewRequestedEvent { id createdAt actor { \(actor) } \(reviewer) }
                  ... on ClosedEvent { createdAt actor { login } }
                }
              }
            }
          }
          \(rateLimit)
        }
        """

    static let history = """
        query($query: String!, $after: String) {
          search(query: $query, type: ISSUE, first: 50, after: $after) {
            pageInfo { hasNextPage endCursor }
            nodes {
              ... on PullRequest {
                id mergedAt author { \(actor) }
                timelineItems(last: 100, itemTypes: [REVIEW_REQUESTED_EVENT, PULL_REQUEST_REVIEW]) {
                  nodes {
                    __typename
                    ... on ReviewRequestedEvent { id createdAt actor { \(actor) } \(reviewer) }
                    ... on PullRequestReview { id state submittedAt author { \(actor) } }
                  }
                }
              }
            }
          }
          \(rateLimit)
        }
        """

    static let teams = """
        query($organization: String!, $login: String!) {
          organization(login: $organization) { teams(first: 100, userLogins: [$login]) { nodes { slug } } }
          \(rateLimit)
        }
        """

    static let repository = """
        query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { id } \(rateLimit) }
        """
}
