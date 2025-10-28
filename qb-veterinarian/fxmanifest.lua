fx_version 'cerulean'

game 'gta5'

author 'OpenAI - gpt-5-codex'
description 'Veterinarian job for QBCore'

shared_script 'config.lua'

client_scripts {
    'client.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

lua54 'yes'
