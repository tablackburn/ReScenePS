# Runtime dependencies for ReScenePS
# These are the modules needed for the module to run
@{
    PSDependOptions = @{
        Target     = 'CurrentUser'
        Parameters = @{
            Repository = 'PSGallery'
        }
    }
    # No external runtime dependencies - all CRC32 functionality is now built-in
}
