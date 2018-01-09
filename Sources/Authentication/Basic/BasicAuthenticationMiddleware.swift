import Fluent
import Vapor

/// Protects a route group, requiring a password authenticatable
/// instance to pass through.
///
/// use `req.requireAuthenticated(A.self)` to fetch the instance.
public final class BasicAuthenticationMiddleware<A>: Middleware
    where A: BasicAuthenticatable, A.Database: QuerySupporting
{
    /// the required password verifier
    public let verifier: PasswordVerifier

    /// The database identifier
    public let database: DatabaseIdentifier<A.Database>

    /// create a new password auth middleware
    public init(
        authenticatable type: A.Type = A.self,
        verifier: PasswordVerifier,
        database: DatabaseIdentifier<A.Database>
    ) {
        self.verifier = verifier
        self.database = database
    }

    /// See Middleware.respond
    public func respond(to req: Request, chainingTo next: Responder) throws -> Future<Response> {
        // if the user has already been authenticated
        // by a previous middleware, continue
        if try req.isAuthenticated(A.self) {
            return try next.respond(to: req)
        }

        // not pre-authed, check for auth data
        guard let password = req.http.headers.basicAuthorization else {
            throw AuthenticationError(
                identifier: "invalidCredentials",
                reason: "Basic authorization header required."
            )
        }

        // get database connection
        return req.connect(to: self.database).flatMap(to: Response.self) { conn in
            // auth user on connection
            return A.authenticate(
                using: password,
                verifier: self.verifier,
                on: conn
            ).flatMap(to: Response.self) { a in
                guard let a = a else {
                    throw Abort(.unauthorized, reason: "Invalid credentials")
                }

                // set authed on request
                try req.authenticate(a)
                return try next.respond(to: req)
            }
        }
    }
}

extension BasicAuthenticatable where Database: QuerySupporting {
    /// Creates a basic auth middleware for this model.
    /// See `BasicAuthenticationMiddleware`.
    public static func basicAuthMiddleware(
        using verifier: PasswordVerifier,
        database: DatabaseIdentifier<Database>? = nil
    ) throws -> BasicAuthenticationMiddleware<Self> {
        return try BasicAuthenticationMiddleware(
            verifier: verifier,
            database: database ?? Self.requireDefaultDatabase()
        )
    }
}