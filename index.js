#!/usr/bin/env node
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { isInitializeRequest } from "@modelcontextprotocol/sdk/types.js";
import { randomUUID } from 'node:crypto';
import express from 'express';
import { readFileSync, readdirSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import AdmZip from 'adm-zip';
import {
  CallToolRequestSchema,
  ErrorCode,
  ListToolsRequestSchema,
  McpError,
} from "@modelcontextprotocol/sdk/types.js";

class TurtleAtlasMcpServer {
  constructor() {
    const __filename = fileURLToPath(import.meta.url);
    this.baseDir = dirname(__filename);

    this.tablesZip = null;

    this.server = new Server(
      {
        name: "turtleatlas-mcp-server",
        version: "1.0.0",
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.setupToolHandlers();
  }

  getTablesZip() {
    if (!this.tablesZip) {
      const zipPath = join(this.baseDir, 'resources', 'tables.zip');
      if (!existsSync(zipPath)) {
        throw new Error(`Tables zip file not found at ${zipPath}`);
      }
      this.tablesZip = new AdmZip(zipPath);
    }
    return this.tablesZip;
  }

  readTableFromZip(tableName) {
    const zip = this.getTablesZip();

    let fileName = tableName.endsWith('.json') || tableName.endsWith('.JSON')
      ? tableName
      : `${tableName}.json`;

    fileName = fileName.toUpperCase();

    let entry = zip.getEntry(`tables/${fileName}`) || zip.getEntry(fileName);

    if (!entry) {
      const entries = zip.getEntries();
      entry = entries.find(e =>
        e.entryName.toUpperCase() === fileName ||
        e.entryName.toUpperCase() === `tables/${fileName}` ||
        e.entryName.toUpperCase().endsWith(`/${fileName}`)
      );
    }

    if (!entry) {
      return null;
    }

    return zip.readAsText(entry);
  }

  listTablesInZip() {
    const zip = this.getTablesZip();
    const entries = zip.getEntries();

    return entries
      .filter(entry => !entry.isDirectory && entry.entryName.toUpperCase().endsWith('.JSON'))
      .map(entry => {
        const name = entry.entryName
          .replace(/^tables\//i, '')
          .replace(/\.json$/i, '');
        return name;
      })
      .sort((a, b) => a.localeCompare(b));
  }

  // Load expert knowledge based on categories — general_db_info.md always included
  loadExpertKnowledge(categories) {
    try {
      let expertContent = '';

      const generalInfoPath = join(this.baseDir, 'resources', 'general_db_info.md');
      if (existsSync(generalInfoPath)) {
        const generalInfo = readFileSync(generalInfoPath, 'utf8');
        expertContent += `\n\n# General Database Information\n\n${generalInfo}`;
      }

      // expertFiles map: keyword → filename in resources/experts/
      // Populate this with your domain's keywords once you add expert files.
      const expertFiles = {};

      const expertsDir = join(this.baseDir, 'resources', 'experts');
      const includedExperts = new Set();

      if (categories && categories.length > 0) {
        for (const category of categories) {
          const categoryLower = category.toLowerCase();

          for (const [key, filename] of Object.entries(expertFiles)) {
            if (categoryLower.includes(key) || key.includes(categoryLower)) {
              if (!includedExperts.has(filename)) {
                const expertPath = join(expertsDir, filename);
                if (existsSync(expertPath)) {
                  const expertData = readFileSync(expertPath, 'utf8');
                  expertContent += `\n\n${expertData}`;
                  includedExperts.add(filename);
                }
              }
            }
          }
        }
      }

      return expertContent;
    } catch (error) {
      console.error(`Error loading expert knowledge: ${error.message}`);
      return '';
    }
  }

  setupToolHandlers(server = this.server) {
    server.setRequestHandler(ListToolsRequestSchema, async () => {
      return {
        tools: [
          {
            name: "list_categories",
            description: "Get a sorted list of all table categories from the knowledge base.",
            inputSchema: {
              type: "object",
              properties: {},
              required: []
            }
          },
          {
            name: "get_tables_by_category",
            description: "Get all tables for a specific category with summaries and descriptions. Supports pagination.",
            inputSchema: {
              type: "object",
              properties: {
                category: {
                  type: "string",
                  description: "The category name to filter tables by"
                },
                limit: {
                  type: "number",
                  description: "Maximum number of tables to return (default: 50)"
                },
                offset: {
                  type: "number",
                  description: "Number of tables to skip (default: 0)"
                }
              },
              required: ["category"]
            }
          },
          {
            name: "list_tables_in_category",
            description: "Get a lightweight list of tables in a category with short summaries. Faster than get_tables_by_category.",
            inputSchema: {
              type: "object",
              properties: {
                category: {
                  type: "string",
                  description: "The category name to filter tables by"
                },
                limit: {
                  type: "number",
                  description: "Maximum number of tables to return (default: 100)"
                },
                offset: {
                  type: "number",
                  description: "Number of tables to skip (default: 0)"
                }
              },
              required: ["category"]
            }
          },
          {
            name: "get_sql_rules",
            description: "Returns the SQL generation rules for this database. Call this first before search_tables or list_experts to get dialect rules, schema conventions, and join patterns.",
            inputSchema: {
              type: "object",
              properties: {},
              required: []
            }
          },
          {
            name: "search_tables",
            description: "Search for tables by keywords across table names, summaries, and descriptions. Returns ranked results.",
            inputSchema: {
              type: "object",
              properties: {
                query: {
                  type: "string",
                  description: "Search query"
                },
                limit: {
                  type: "number",
                  description: "Maximum number of results to return (default: 20)"
                },
                categories: {
                  type: "array",
                  items: { type: "string" },
                  description: "Optional: filter results to specific categories"
                },
                search_in: {
                  type: "array",
                  items: { type: "string", enum: ["name", "summary", "description"] },
                  description: "Optional: where to search (default: all fields)"
                }
              },
              required: ["query"]
            }
          },
          {
            name: "get_table_details",
            description: "Get the complete schema and column details for a specific table. Returns the full JSON structure including columns, data types, constraints, and relationships.",
            inputSchema: {
              type: "object",
              properties: {
                table_name: {
                  type: "string",
                  description: "The name of the table to retrieve. Case-insensitive."
                }
              },
              required: ["table_name"]
            }
          },
          {
            name: "list_experts",
            description: "List all available expert knowledge files with names and descriptions. Call this to discover which domain experts are relevant to the user's question, then call get_expert to load the full detail.",
            inputSchema: {
              type: "object",
              properties: {},
              required: []
            }
          },
          {
            name: "get_expert",
            description: "Load the full content of a specific expert knowledge file by name. Always call list_experts first to discover available experts.",
            inputSchema: {
              type: "object",
              properties: {
                name: {
                  type: "string",
                  description: "The expert file name as returned by list_experts (e.g., 'orders.md')"
                }
              },
              required: ["name"]
            }
          },
          {
            name: "list_journeys",
            description: "List available detailed journey files. Journeys are deep-detail extracts of specific processes or workflows. Use when you need complete business rules, field validations, or state transitions.",
            inputSchema: {
              type: "object",
              properties: {
                domain: {
                  type: "string",
                  description: "Optional domain filter (e.g. 'order'). If omitted, all journeys are listed."
                }
              },
              required: []
            }
          },
          {
            name: "get_journey",
            description: "Load the full content of a specific journey file by name, as returned by list_journeys. Journey files are much richer than expert files — load only what is directly relevant to the conversation.",
            inputSchema: {
              type: "object",
              properties: {
                name: {
                  type: "string",
                  description: "The journey file name as returned by list_journeys"
                }
              },
              required: ["name"]
            }
          }
        ]
      };
    });

    server.setRequestHandler(CallToolRequestSchema, async (request) => {
      const { name, arguments: args } = request.params;

      switch (name) {
        case "get_sql_rules":
          return this.handleGetSqlRules();
        case "list_categories":
          return this.handleListCategories(args);
        case "get_tables_by_category":
          return this.handleGetTablesByCategory(args);
        case "list_tables_in_category":
          return this.handleListTablesInCategory(args);
        case "search_tables":
          return this.handleSearchTables(args);
        case "get_table_details":
          return this.handleGetTableDetails(args);
        case "list_experts":
          return this.handleListExperts(args);
        case "get_expert":
          return this.handleGetExpert(args);
        case "list_journeys":
          return this.handleListJourneys(args);
        case "get_journey":
          return this.handleGetJourney(args);
        default:
          throw new McpError(
            ErrorCode.MethodNotFound,
            `Unknown tool: ${name}`
          );
      }
    });
  }

  handleGetSqlRules() {
    const generalInfoPath = join(this.baseDir, 'resources', 'general_db_info.md');
    if (!existsSync(generalInfoPath)) {
      return { content: [{ type: 'text', text: 'SQL rules file not found.' }] };
    }
    const rules = readFileSync(generalInfoPath, 'utf8');
    return { content: [{ type: 'text', text: rules }] };
  }

  handleListCategories(args) {
    try {
      const tableOverviewPath = join(this.baseDir, 'resources', 'table_overview.json');
      let tableOverviewContent = readFileSync(tableOverviewPath, 'utf8');

      if (tableOverviewContent.charCodeAt(0) === 0xFEFF) {
        tableOverviewContent = tableOverviewContent.slice(1);
      }

      const tableOverview = JSON.parse(tableOverviewContent);
      const categoriesSet = new Set();

      if (tableOverview.files && Array.isArray(tableOverview.files)) {
        for (const file of tableOverview.files) {
          if (file.categories) {
            if (Array.isArray(file.categories)) {
              file.categories.forEach(cat => categoriesSet.add(cat));
            } else if (typeof file.categories === 'string') {
              categoriesSet.add(file.categories);
            }
          }
        }
      }

      const sortedCategories = Array.from(categoriesSet).sort((a, b) => a.localeCompare(b));
      return {
        content: [{ type: "text", text: sortedCategories.join('\n') }]
      };
    } catch (error) {
      throw new McpError(ErrorCode.InternalError, `Error reading table categories: ${error.message}`);
    }
  }

  handleGetTablesByCategory(args) {
    try {
      const { category, limit = 50, offset = 0 } = args;

      if (!category) {
        throw new McpError(ErrorCode.InvalidParams, "Category parameter is required");
      }

      const tableOverviewPath = join(this.baseDir, 'resources', 'table_overview.json');
      let tableOverviewContent = readFileSync(tableOverviewPath, 'utf8');
      if (tableOverviewContent.charCodeAt(0) === 0xFEFF) tableOverviewContent = tableOverviewContent.slice(1);
      const tableOverview = JSON.parse(tableOverviewContent);

      const categoriesSet = new Set();
      const matchingTables = [];

      if (tableOverview.files && Array.isArray(tableOverview.files)) {
        for (const file of tableOverview.files) {
          if (file.categories) {
            const fileCategories = Array.isArray(file.categories) ? file.categories : [file.categories];
            fileCategories.forEach(cat => categoriesSet.add(cat));
            if (fileCategories.some(cat => cat.toLowerCase() === category.toLowerCase())) {
              matchingTables.push({
                filename: file.filename,
                summary: file.summary || 'No summary available',
                description: file.description || 'No description available',
                categories: fileCategories
              });
            }
          }
        }
      }

      if (matchingTables.length === 0) {
        const sortedCategories = Array.from(categoriesSet).sort((a, b) => a.localeCompare(b));
        const categoryExists = sortedCategories.some(cat => cat.toLowerCase() === category.toLowerCase());
        if (!categoryExists) {
          return {
            content: [{ type: "text", text: `Category "${category}" does not exist.\n\nAvailable categories:\n${sortedCategories.join('\n')}` }]
          };
        }
      }

      matchingTables.sort((a, b) => a.filename.localeCompare(b.filename));
      const totalCount = matchingTables.length;
      const paginatedTables = matchingTables.slice(offset, offset + limit);
      const hasMore = (offset + limit) < totalCount;

      let content = `Found ${totalCount} table(s) in category "${category}"\n`;
      content += `Showing ${paginatedTables.length} tables (offset: ${offset}, limit: ${limit})\n`;
      if (hasMore) content += `**Note:** ${totalCount - (offset + limit)} more tables available. Use offset=${offset + limit} to see more.\n`;
      content += `\n`;

      for (const table of paginatedTables) {
        const tableName = table.filename.replace('.json', '');
        content += `## ${tableName}\n`;
        content += `**Categories:** ${table.categories.join(', ')}\n\n`;
        content += `**Summary:** ${table.summary}\n\n`;
        if (table.description && table.description !== 'No description available') {
          content += `**Description:** ${table.description}\n\n`;
        }
        content += `---\n\n`;
      }

      const expertKnowledge = this.loadExpertKnowledge([category]);
      if (expertKnowledge) {
        content += `\n\n---\n\n# Expert Knowledge\n\n${expertKnowledge}`;
      }

      return { content: [{ type: "text", text: content }] };
    } catch (error) {
      if (error instanceof McpError) throw error;
      throw new McpError(ErrorCode.InternalError, `Error retrieving tables by category: ${error.message}`);
    }
  }

  handleListTablesInCategory(args) {
    try {
      const { category, limit = 100, offset = 0 } = args;

      if (!category) {
        throw new McpError(ErrorCode.InvalidParams, "Category parameter is required");
      }

      const tableOverviewPath = join(this.baseDir, 'resources', 'table_overview.json');
      let tableOverviewContent = readFileSync(tableOverviewPath, 'utf8');
      if (tableOverviewContent.charCodeAt(0) === 0xFEFF) tableOverviewContent = tableOverviewContent.slice(1);
      const tableOverview = JSON.parse(tableOverviewContent);

      const categoriesSet = new Set();
      const matchingTables = [];

      if (tableOverview.files && Array.isArray(tableOverview.files)) {
        for (const file of tableOverview.files) {
          if (file.categories) {
            const fileCategories = Array.isArray(file.categories) ? file.categories : [file.categories];
            fileCategories.forEach(cat => categoriesSet.add(cat));
            if (fileCategories.some(cat => cat.toLowerCase() === category.toLowerCase())) {
              const summary = file.summary || 'No summary available';
              matchingTables.push({
                filename: file.filename,
                short_summary: summary.length > 150 ? summary.substring(0, 150) + '...' : summary,
                categories: fileCategories
              });
            }
          }
        }
      }

      if (matchingTables.length === 0) {
        const sortedCategories = Array.from(categoriesSet).sort((a, b) => a.localeCompare(b));
        const categoryExists = sortedCategories.some(cat => cat.toLowerCase() === category.toLowerCase());
        if (!categoryExists) {
          return {
            content: [{ type: "text", text: `Category "${category}" does not exist.\n\nAvailable categories:\n${sortedCategories.join('\n')}` }]
          };
        }
      }

      matchingTables.sort((a, b) => a.filename.localeCompare(b.filename));
      const totalCount = matchingTables.length;
      const paginatedTables = matchingTables.slice(offset, offset + limit);
      const hasMore = (offset + limit) < totalCount;

      let content = `# ${category} Category - ${totalCount} Tables\n\n`;
      content += `Showing ${paginatedTables.length} tables (offset: ${offset}, limit: ${limit})\n`;
      if (hasMore) content += `${totalCount - (offset + limit)} more tables available. Use offset=${offset + limit} to see more.\n`;
      content += `\n---\n\n`;

      for (const table of paginatedTables) {
        const tableName = table.filename.replace('.json', '');
        content += `**${tableName}** - ${table.short_summary}\n`;
        content += `*Categories: ${table.categories.join(', ')}*\n\n`;
      }

      content += `\n---\n\nUse \`get_table_details\` to see full schema, or \`get_tables_by_category\` for complete summaries.\n`;

      const expertKnowledge = this.loadExpertKnowledge([category]);
      if (expertKnowledge) content += `\n\n---\n\n# Expert Knowledge\n\n${expertKnowledge}`;

      return { content: [{ type: "text", text: content }] };
    } catch (error) {
      if (error instanceof McpError) throw error;
      throw new McpError(ErrorCode.InternalError, `Error listing tables in category: ${error.message}`);
    }
  }

  handleSearchTables(args) {
    try {
      const { query, limit = 20, categories = null, search_in = ["name", "summary", "description"] } = args;

      if (!query || query.trim().length === 0) {
        throw new McpError(ErrorCode.InvalidParams, "Query parameter is required and cannot be empty");
      }

      const tableOverviewPath = join(this.baseDir, 'resources', 'table_overview.json');
      let tableOverviewContent = readFileSync(tableOverviewPath, 'utf8');
      if (tableOverviewContent.charCodeAt(0) === 0xFEFF) tableOverviewContent = tableOverviewContent.slice(1);
      const tableOverview = JSON.parse(tableOverviewContent);

      const searchTerms = query.toLowerCase().split(/\s+/).filter(term => term.length > 0);
      const results = [];

      if (tableOverview.files && Array.isArray(tableOverview.files)) {
        for (const file of tableOverview.files) {
          const fileCategories = Array.isArray(file.categories) ? file.categories : [file.categories];

          if (categories && categories.length > 0) {
            const hasMatchingCategory = fileCategories.some(cat =>
              categories.some(reqCat => reqCat.toLowerCase() === cat.toLowerCase())
            );
            if (!hasMatchingCategory) continue;
          }

          const tableName = file.filename.replace('.json', '');
          const summary = file.summary || '';
          const description = file.description || '';

          let score = 0;
          let matchedIn = [];
          let highlights = [];

          if (search_in.includes('name')) {
            const lowerName = tableName.toLowerCase();
            searchTerms.forEach(term => {
              if (lowerName.includes(term)) {
                score += 3;
                if (!matchedIn.includes('name')) matchedIn.push('name');
                highlights.push(`Table name contains "${term}"`);
              }
            });
          }

          if (search_in.includes('summary') && summary) {
            const lowerSummary = summary.toLowerCase();
            searchTerms.forEach(term => {
              if (lowerSummary.includes(term)) {
                score += 2;
                if (!matchedIn.includes('summary')) matchedIn.push('summary');
                const index = lowerSummary.indexOf(term);
                const start = Math.max(0, index - 30);
                const end = Math.min(summary.length, index + term.length + 30);
                highlights.push(`...${summary.substring(start, end)}...`);
              }
            });
          }

          if (search_in.includes('description') && description) {
            const lowerDesc = description.toLowerCase();
            searchTerms.forEach(term => {
              if (lowerDesc.includes(term)) {
                score += 1;
                if (!matchedIn.includes('description')) matchedIn.push('description');
              }
            });
          }

          if (score > 0) {
            results.push({
              table: tableName,
              score,
              categories: fileCategories,
              summary: summary.substring(0, 200) + (summary.length > 200 ? '...' : ''),
              matched_in: matchedIn,
              highlights: highlights.slice(0, 2)
            });
          }
        }
      }

      results.sort((a, b) => b.score - a.score);
      const topResults = results.slice(0, limit);

      let content = `# Search Results for "${query}"\n\n`;
      content += `Found ${results.length} matching table(s), showing top ${topResults.length}\n\n`;

      if (topResults.length === 0) {
        content += `No tables found matching your query.\n\nTry different keywords or use \`list_categories\` to browse.\n`;
      } else {
        for (let i = 0; i < topResults.length; i++) {
          const result = topResults[i];
          content += `## ${i + 1}. ${result.table} (score: ${result.score})\n\n`;
          content += `**Categories:** ${result.categories.join(', ')}\n\n`;
          content += `**Matched in:** ${result.matched_in.join(', ')}\n\n`;
          if (result.highlights.length > 0) {
            content += `**Highlights:**\n`;
            result.highlights.forEach(h => content += `- ${h}\n`);
            content += `\n`;
          }
          content += `**Summary:** ${result.summary}\n\n---\n\n`;
        }
        content += `Use \`get_table_details\` to see the full schema of a specific table.\n`;
      }

      if (topResults.length > 0) {
        const uniqueCategories = [...new Set(topResults.flatMap(r => r.categories))];
        const expertKnowledge = this.loadExpertKnowledge(uniqueCategories);
        if (expertKnowledge) content += `\n\n---\n\n# Expert Knowledge\n\n${expertKnowledge}`;
      }

      return { content: [{ type: "text", text: content }] };
    } catch (error) {
      if (error instanceof McpError) throw error;
      throw new McpError(ErrorCode.InternalError, `Error searching tables: ${error.message}`);
    }
  }

  handleListExperts(args) {
    try {
      const expertsDir = join(this.baseDir, 'resources', 'experts');
      const files = readdirSync(expertsDir).filter(f => f.endsWith('.md')).sort();

      if (files.length === 0) {
        return { content: [{ type: 'text', text: 'No expert files found. See CLAUDE.md for how to add expert knowledge.' }] };
      }

      const experts = files.map(filename => {
        const content = readFileSync(join(expertsDir, filename), 'utf8');
        const lines = content.split('\n');
        const heading = lines.find(l => l.startsWith('# '))?.replace('# ', '').trim() || filename;
        const description = lines.find((l, i) => i > 0 && l.trim() && !l.startsWith('#'))?.trim() || '';
        return { name: filename, title: heading, description };
      });

      const content = `Available expert knowledge files:\n\n` +
        experts.map(e => `- **${e.name}**: ${e.title} — ${e.description}`).join('\n');

      return { content: [{ type: 'text', text: content }] };
    } catch (error) {
      throw new McpError(ErrorCode.InternalError, `Error listing experts: ${error.message}`);
    }
  }

  handleGetExpert(args) {
    try {
      const { name } = args;
      if (!name) throw new McpError(ErrorCode.InvalidParams, 'name parameter is required');
      const expertsDir = join(this.baseDir, 'resources', 'experts');
      const expertPath = join(expertsDir, name);
      if (!existsSync(expertPath)) {
        const available = readdirSync(expertsDir).filter(f => f.endsWith('.md')).join(', ') || 'none';
        throw new McpError(ErrorCode.InvalidParams, `Expert '${name}' not found. Available: ${available}`);
      }
      const content = readFileSync(expertPath, 'utf8');
      return { content: [{ type: 'text', text: content }] };
    } catch (error) {
      if (error instanceof McpError) throw error;
      throw new McpError(ErrorCode.InternalError, `Error loading expert: ${error.message}`);
    }
  }

  handleListJourneys(args) {
    try {
      const journeysDir = join(this.baseDir, 'resources', 'journeys');
      if (!existsSync(journeysDir)) {
        return { content: [{ type: 'text', text: 'No journeys directory found.' }] };
      }
      const { domain } = args || {};
      let files = readdirSync(journeysDir).filter(f => f.endsWith('.md')).sort();
      if (domain) files = files.filter(f => f.startsWith(domain.toLowerCase()));

      if (files.length === 0) {
        return { content: [{ type: 'text', text: 'No journey files found. See CLAUDE.md for how to add journey knowledge.' }] };
      }

      const journeys = files.map(filename => {
        const content = readFileSync(join(journeysDir, filename), 'utf8');
        const lines = content.split('\n');
        const heading = lines.find(l => l.startsWith('# '))?.replace(/^#\s+/, '').trim() || filename;
        const triggerIdx = lines.findIndex(l => l.toLowerCase().includes('trigger'));
        const description = triggerIdx >= 0
          ? lines.slice(triggerIdx, triggerIdx + 3).map(l => l.trim()).filter(l => l && !l.startsWith('#')).join(' ')
          : lines.find((l, i) => i > 0 && l.trim() && !l.startsWith('#'))?.trim() || '';
        return { name: filename, title: heading, description };
      });

      const content = `Available journey files${domain ? ` (domain: ${domain})` : ''}:\n\n` +
        journeys.map(j => `- **${j.name}**: ${j.title} — ${j.description}`).join('\n') +
        '\n\nCall get_journey(name) to load the full detail of a specific journey.';

      return { content: [{ type: 'text', text: content }] };
    } catch (error) {
      throw new McpError(ErrorCode.InternalError, `Error listing journeys: ${error.message}`);
    }
  }

  handleGetJourney(args) {
    try {
      const { name } = args;
      if (!name) throw new McpError(ErrorCode.InvalidParams, 'name parameter is required');
      const journeysDir = join(this.baseDir, 'resources', 'journeys');
      const journeyPath = join(journeysDir, name);
      if (!existsSync(journeyPath)) {
        const available = existsSync(journeysDir)
          ? readdirSync(journeysDir).filter(f => f.endsWith('.md')).join(', ')
          : 'none';
        throw new McpError(ErrorCode.InvalidParams, `Journey '${name}' not found. Available: ${available}`);
      }
      const content = readFileSync(journeyPath, 'utf8');
      return { content: [{ type: 'text', text: content }] };
    } catch (error) {
      if (error instanceof McpError) throw error;
      throw new McpError(ErrorCode.InternalError, `Error loading journey: ${error.message}`);
    }
  }

  handleGetTableDetails(args) {
    try {
      const { table_name } = args;
      if (!table_name) throw new McpError(ErrorCode.InvalidParams, "table_name parameter is required");

      const tableContent = this.readTableFromZip(table_name);

      if (!tableContent) {
        const availableTables = this.listTablesInZip();
        const searchTerm = table_name.replace(/\.json$/i, '').toUpperCase();
        const similarTables = availableTables
          .filter(t => t.toUpperCase().includes(searchTerm) || searchTerm.includes(t.toUpperCase()))
          .slice(0, 10);

        let errorMessage = `Table "${table_name}" not found in the tables archive.\n\n`;
        if (similarTables.length > 0) errorMessage += `Did you mean one of these?\n${similarTables.join('\n')}\n\n`;
        errorMessage += `Total tables available: ${availableTables.length}\n`;
        errorMessage += `Use get_tables_by_category to browse tables by category.`;

        return { content: [{ type: "text", text: errorMessage }] };
      }

      let tableData;
      try {
        tableData = JSON.parse(tableContent);
      } catch (parseError) {
        throw new McpError(ErrorCode.InternalError, `Error parsing table data: ${parseError.message}`);
      }

      const tableName = table_name.replace(/\.json$/i, '').toUpperCase();
      const content = `# ${tableName} - Complete Table Details\n\n\`\`\`json\n${JSON.stringify(tableData, null, 2)}\n\`\`\`\n`;

      return { content: [{ type: "text", text: content }] };
    } catch (error) {
      if (error instanceof McpError) throw error;
      throw new McpError(ErrorCode.InternalError, `Error retrieving table details: ${error.message}`);
    }
  }

  async runStdio() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error("turtleatlas-mcp server running on stdio");
  }

  async runHttp(port) {
    const transports = {};
    const app = express();
    app.use(express.json());

    app.get('/health', (_req, res) => {
      res.json({
        status: 'healthy',
        service: 'turtleatlas-mcp-server',
        version: '1.0.0',
        transport: 'Streamable HTTP',
        uptime: process.uptime(),
        timestamp: new Date().toISOString(),
        activeSessions: Object.keys(transports).length,
      });
    });

    app.post('/mcp', async (req, res) => {
      const sessionId = req.headers['mcp-session-id'];
      let transport;

      if (sessionId && transports[sessionId]) {
        transport = transports[sessionId];
      } else if (!sessionId && isInitializeRequest(req.body)) {
        transport = new StreamableHTTPServerTransport({
          sessionIdGenerator: () => randomUUID(),
          onsessioninitialized: (id) => { transports[id] = transport; },
        });
        transport.onclose = () => {
          const sid = transport.sessionId;
          if (sid) delete transports[sid];
        };
        const sessionServer = new Server(
          { name: "turtleatlas-mcp-server", version: "1.0.0" },
          { capabilities: { tools: {} } }
        );
        this.setupToolHandlers(sessionServer);
        await sessionServer.connect(transport);
        await transport.handleRequest(req, res, req.body);
        return;
      } else {
        res.status(400).json({ jsonrpc: '2.0', error: { code: -32000, message: 'Bad Request: No valid session ID' }, id: null });
        return;
      }

      await transport.handleRequest(req, res, req.body);
    });

    app.get('/mcp', async (req, res) => {
      const sessionId = req.headers['mcp-session-id'];
      if (!sessionId || !transports[sessionId]) {
        res.status(400).send('Invalid or missing session ID');
        return;
      }
      await transports[sessionId].handleRequest(req, res);
    });

    app.delete('/mcp', async (req, res) => {
      const sessionId = req.headers['mcp-session-id'];
      if (!sessionId || !transports[sessionId]) {
        res.status(400).send('Invalid or missing session ID');
        return;
      }
      await transports[sessionId].handleRequest(req, res);
    });

    const host = process.env.HOST || '0.0.0.0';
    app.listen(port, host, () => {
      console.error(`turtleatlas-mcp server (Streamable HTTP) listening on http://${host}:${port}/mcp`);
    });
  }

  async run() {
    const portArg = process.argv.find(a => a.startsWith('--port='));
    const port = portArg
      ? parseInt(portArg.split('=')[1], 10)
      : process.env.MCP_PORT
        ? parseInt(process.env.MCP_PORT, 10)
        : null;

    if (port) {
      await this.runHttp(port);
    } else {
      await this.runStdio();
    }
  }
}

const server = new TurtleAtlasMcpServer();
server.run().catch(console.error);
