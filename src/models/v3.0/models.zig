pub const OpenApiDocument = @import("openapi.zig").OpenApiDocument;

// Export all types from the various modules
pub const Info = @import("info.zig").Info;
pub const Contact = @import("info.zig").Contact;
pub const License = @import("info.zig").License;

pub const Server = @import("server.zig").Server;
pub const ServerVariable = @import("server.zig").ServerVariable;

pub const ExternalDocumentation = @import("externaldocs.zig").ExternalDocumentation;

pub const Tag = @import("tag.zig").Tag;

pub const Reference = @import("reference.zig").Reference;

pub const Schema = @import("schema.zig").Schema;
pub const SchemaOrReference = @import("schema.zig").SchemaOrReference;
pub const XML = @import("schema.zig").XML;
pub const Discriminator = @import("schema.zig").Discriminator;
pub const AdditionalProperties = @import("schema.zig").AdditionalProperties;

pub const Example = @import("media.zig").Example;
pub const ExampleOrReference = @import("media.zig").ExampleOrReference;
pub const Header = @import("media.zig").Header;
pub const HeaderOrReference = @import("media.zig").HeaderOrReference;
pub const Encoding = @import("media.zig").Encoding;
pub const MediaType = @import("media.zig").MediaType;

pub const Parameter = @import("parameter.zig").Parameter;
pub const ParameterOrReference = @import("parameter.zig").ParameterOrReference;

pub const RequestBody = @import("requestbody.zig").RequestBody;
pub const RequestBodyOrReference = @import("requestbody.zig").RequestBodyOrReference;

pub const Response = @import("response.zig").Response;
pub const ResponseOrReference = @import("response.zig").ResponseOrReference;
pub const Responses = @import("response.zig").Responses;

pub const PathItem = @import("paths.zig").PathItem;
pub const Paths = @import("paths.zig").Paths;

pub const Operation = @import("operation.zig").Operation;

pub const Link = @import("link.zig").Link;
pub const LinkOrReference = @import("link.zig").LinkOrReference;

pub const Callback = @import("callback.zig").Callback;
pub const CallbackOrReference = @import("callback.zig").CallbackOrReference;

pub const SecurityRequirement = @import("security.zig").SecurityRequirement;
pub const SecurityScheme = @import("security.zig").SecurityScheme;
pub const SecuritySchemeOrReference = @import("security.zig").SecuritySchemeOrReference;
pub const OAuthFlows = @import("security.zig").OAuthFlows;
pub const ImplicitOAuthFlow = @import("security.zig").ImplicitOAuthFlow;
pub const PasswordOAuthFlow = @import("security.zig").PasswordOAuthFlow;
pub const ClientCredentialsFlow = @import("security.zig").ClientCredentialsFlow;
pub const AuthorizationCodeOAuthFlow = @import("security.zig").AuthorizationCodeOAuthFlow;
pub const APIKeySecurityScheme = @import("security.zig").APIKeySecurityScheme;
pub const HTTPSecurityScheme = @import("security.zig").HTTPSecurityScheme;
pub const OAuth2SecurityScheme = @import("security.zig").OAuth2SecurityScheme;
pub const OpenIdConnectSecurityScheme = @import("security.zig").OpenIdConnectSecurityScheme;

pub const Components = @import("components.zig").Components;
