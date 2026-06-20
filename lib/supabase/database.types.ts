export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      commodities: {
        Row: {
          createdat: string
          currentquantity: number
          id: string
          minthreshold: number
          name: string
          program: string
          unit: string
          updatedat: string
        }
        Insert: {
          createdat?: string
          currentquantity?: number
          id?: string
          minthreshold?: number
          name: string
          program: string
          unit: string
          updatedat?: string
        }
        Update: {
          createdat?: string
          currentquantity?: number
          id?: string
          minthreshold?: number
          name?: string
          program?: string
          unit?: string
          updatedat?: string
        }
        Relationships: []
      }
      deliveries: {
        Row: {
          createdat: string
          deliverydate: string
          id: string
          items: Json
          providerid: string
          reference: string | null
          status: string
          supplierid: string
          suppliername: string
          syncstatus: string
          updatedat: string
        }
        Insert: {
          createdat?: string
          deliverydate: string
          id?: string
          items?: Json
          providerid: string
          reference?: string | null
          status?: string
          supplierid: string
          suppliername: string
          syncstatus?: string
          updatedat?: string
        }
        Update: {
          createdat?: string
          deliverydate?: string
          id?: string
          items?: Json
          providerid?: string
          reference?: string | null
          status?: string
          supplierid?: string
          suppliername?: string
          syncstatus?: string
          updatedat?: string
        }
        Relationships: [
          {
            foreignKeyName: "deliveries_providerid_fkey"
            columns: ["providerid"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "deliveries_supplierid_fkey"
            columns: ["supplierid"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      stock_movements: {
        Row: {
          commodityid: string
          createdat: string
          id: string
          notes: string | null
          quantity: number
          reason: string
          syncstatus: string
          type: string
          userid: string
        }
        Insert: {
          commodityid: string
          createdat?: string
          id?: string
          notes?: string | null
          quantity: number
          reason: string
          syncstatus?: string
          type: string
          userid: string
        }
        Update: {
          commodityid?: string
          createdat?: string
          id?: string
          notes?: string | null
          quantity?: number
          reason?: string
          syncstatus?: string
          type?: string
          userid?: string
        }
        Relationships: [
          {
            foreignKeyName: "stock_movements_commodityid_fkey"
            columns: ["commodityid"]
            isOneToOne: false
            referencedRelation: "commodities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stock_movements_userid_fkey"
            columns: ["userid"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      test_records: {
        Row: {
          actgiven: boolean | null
          ageband: string
          artlinkage: string | null
          clientid: string
          clientname: string
          createdat: string
          determinetest: string | null
          feverpresented: boolean | null
          hivcounselling: boolean | null
          hivsttype: string | null
          id: string
          mrdtpositive: boolean | null
          mrdttested: boolean | null
          notes: string | null
          pregnant: boolean | null
          prepaccepted: boolean | null
          prepassessed: boolean | null
          prepcontinued: boolean | null
          prepeligible: boolean | null
          prepoffered: boolean | null
          preprefsource: string | null
          prepstarted: boolean | null
          program: string
          referralfacility: string | null
          sex: string
          syncstatus: string
          tbscreening: string | null
          testdate: string
          updatedat: string
          userid: string
          visittype: string
        }
        Insert: {
          actgiven?: boolean | null
          ageband: string
          artlinkage?: string | null
          clientid: string
          clientname: string
          createdat?: string
          determinetest?: string | null
          feverpresented?: boolean | null
          hivcounselling?: boolean | null
          hivsttype?: string | null
          id?: string
          mrdtpositive?: boolean | null
          mrdttested?: boolean | null
          notes?: string | null
          pregnant?: boolean | null
          prepaccepted?: boolean | null
          prepassessed?: boolean | null
          prepcontinued?: boolean | null
          prepeligible?: boolean | null
          prepoffered?: boolean | null
          preprefsource?: string | null
          prepstarted?: boolean | null
          program: string
          referralfacility?: string | null
          sex: string
          syncstatus?: string
          tbscreening?: string | null
          testdate: string
          updatedat?: string
          userid: string
          visittype: string
        }
        Update: {
          actgiven?: boolean | null
          ageband?: string
          artlinkage?: string | null
          clientid?: string
          clientname?: string
          createdat?: string
          determinetest?: string | null
          feverpresented?: boolean | null
          hivcounselling?: boolean | null
          hivsttype?: string | null
          id?: string
          mrdtpositive?: boolean | null
          mrdttested?: boolean | null
          notes?: string | null
          pregnant?: boolean | null
          prepaccepted?: boolean | null
          prepassessed?: boolean | null
          prepcontinued?: boolean | null
          prepeligible?: boolean | null
          prepoffered?: boolean | null
          preprefsource?: string | null
          prepstarted?: boolean | null
          program?: string
          referralfacility?: string | null
          sex?: string
          syncstatus?: string
          tbscreening?: string | null
          testdate?: string
          updatedat?: string
          userid?: string
          visittype?: string
        }
        Relationships: [
          {
            foreignKeyName: "test_records_userid_fkey"
            columns: ["userid"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          adminscope: string
          approvalstatus: string
          approvedat: string | null
          approvedby: string | null
          createdat: string
          email: string
          facilityname: string | null
          forcepasswordchange: boolean
          id: string
          lastlogin: string | null
          lga: string | null
          providertype: string | null
          role: string
          state: string | null
          updatedat: string
          username: string
        }
        Insert: {
          adminscope?: string
          approvalstatus?: string
          approvedat?: string | null
          approvedby?: string | null
          createdat?: string
          email: string
          facilityname?: string | null
          forcepasswordchange?: boolean
          id: string
          lastlogin?: string | null
          lga?: string | null
          providertype?: string | null
          role: string
          state?: string | null
          updatedat?: string
          username: string
        }
        Update: {
          adminscope?: string
          approvalstatus?: string
          approvedat?: string | null
          approvedby?: string | null
          createdat?: string
          email?: string
          facilityname?: string | null
          forcepasswordchange?: boolean
          id?: string
          lastlogin?: string | null
          lga?: string | null
          providertype?: string | null
          role?: string
          state?: string | null
          updatedat?: string
          username?: string
        }
        Relationships: [
          {
            foreignKeyName: "users_approvedby_fkey"
            columns: ["approvedby"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
