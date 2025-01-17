﻿using PSModule.Properties;
using PSModule.UftMobile.SDK.Enums;
using System.Management.Automation;

namespace PSModule.UftMobile.SDK.Util
{
    public class Credentials
    {
        private readonly string _usernameOrClientId;
        private readonly string _passwordOrSecret;
        private readonly int _tenantId;

        public string UsernameOrClientId => _usernameOrClientId;
        public string PasswordOrSecret => _passwordOrSecret;
        public int TenantId => _tenantId;

        public Credentials(string usernameorClientId, string passwordOrSecret, int tenantId = 0)
        {
            if (usernameorClientId.IsNullOrWhiteSpace())
                throw new UftMobileException(Resources.MissingUsernameOrClientId, ErrorCategory.InvalidArgument);

            _usernameOrClientId = usernameorClientId;
            _passwordOrSecret = passwordOrSecret;
            _tenantId = tenantId;
        }
    }
}
